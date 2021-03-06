function country_risk_economic_loss = cr_economic_loss_calc(country_risk,economic_data_file)
% MODULE:
%   country_risk
% NAME:
%   cr_economic_loss_calc
% PURPOSE:
%   Calculate the economic loss, i.e. the impact of a natural disaster on a
%   country's economy
%   method: Starting point for the economic loss calculation is 
%   damage(event_i), i.e. the damage calculated by climada_EDS_calc. 
%   The economic loss caused by the natural disaster is then calculated
%   according to:
%   economic_loss(event_i) = damage(event_i)*loss_multiplier
%   with
%   loss_multiplier = 
%   1 + cr_get_damage_weight(damage(event_i)/GDP) * country_damage_factor
%       with 
%           cr_get_damage_weight: function that determines how much weight a
%           damage should be given based on its ratio to GDP
%           country_damage_factor = (1/financial_strength +
%           BI_and_supply_chain_risk + natural_hazard_economic_exposure 
%           - disaster_resilience)
%           Hence, country_damage_factor consists of four terms: 
%               - financial_strength measures a country's economic health and
%               ability to finance the recovery
%               - BI_and_supply_chain_risk measures a country's risk of
%               disaster-related business and supply chain interruption
%               - natural_hazard_economic_exposure assesses which countries 
%               have a concentration of their total economic output exposed to 
%               natural hazards
%               - disaster_resilience measures the quality of a country's 
%               natural hazard risk management, i.e., the country's 
%               "preparedness" to deal with the consequences of a disaster 
%   See economic_indicators_mastertable.xls (in climada/data/system for 
%   more information on the components of country_damage_factor
% PREVIOUS STEP:
%   country_risk = country_risk_calc('country_i')
% CALLING SEQUENCE:
%   country_risk_economic_loss = cr_economic_loss_calc(country_risk)
% EXAMPLE:
%   country_risk_economic_loss =
%   cr_economic_loss_calc(country_risk_Switzerland)
% INPUT:
%   country_risk: A struct generated by country_risk_calc
%   containing the fields
%       peril_ID:       ID(s) of the peril(s) the country is exposed to
%       raw_data_file:  the file used to generste the event set
%       hazard_set_file:file with the stored hazard
%       EDS:            event damage set(s) for the peril(s) 
%   country_risk can contain information on a single country or on multiple
%   countries
% OPTIONAL INPUT: 
%   economic_data_file: the filename of the excel file with the raw data
%       (country-specific economic and resilience data used to calculate the
%       economic loss)
%       If empty, the code uses the default table as provied with core
%       climada, should it not exist, it prompts the user to locate the file 
% OUTPUT:
% 	country_risk_economic_loss: The same struct as the input, but
% 	country_risk.res.hazard.EDS.damage has been replaced by
% 	country_risk.res.hazard.EDS.economic_loss (for all countries and 
%   perils in country_risk)
%
% MODIFICATION HISTORY:
% Melanie Bieli, melanie.bieli@bluewin.ch, 20141229, initial
% Melanie Bieli, melanie.bieli@bluewin.ch, 20150105, compatibility with multiple country input
% David N. Bresch, david.bresch@gmail.com, 20150203, economic_indicators_mastertable part of core climada
% Melanie Bieli, melanie.bieli@bluewin.ch, 20150210, economic_indicators_mastertable: extended and standard version
%
% TO DO: Modify the function such that it can also handle hazard event sets
% that have been generated by functions other than country_risk_calc, e.g.,
% by eq_global_hazard_set or climada_tc_hazard_set
% ANSWER: for the time being, running this afer country_risk_calc is OK.
%-

% initialize output
%country_risk_economic_loss = []; % init output
%country_risk_economic_loss = struct([]);
country_risk_economic_loss = country_risk;

% check input arguments
if ~exist('economic_data_file','var'),economic_data_file='';end
if ~exist('country_risk','var')
    fprintf('Error: Input argument ''country_risk'' is needed.\n')
    return;
end

% set global variables
global climada_global
if ~climada_init_vars,return;end % init/import global variables

% persistent iteration_counter; % counts recursive function calls to deal with multiple countries
% if (isempty(iteration_counter))
%      iteration_counter = -1;
% end 
% iteration_counter = iteration_counter + 1;

% PARAMETERS
%
%
% For the income group, we assume that the relationship between loss and
% GNI per capita (based on which a country's income group is defined) is an
% inverted U shape (highest losses for middle income countries, smaller
% losses for low and high income countries)
% see e.g. Okuyama, Yasuhide. Economic Impacts of Natural Disasters:
% Development Issues and Applications
% http://nexus-idrim.net/idrim09/Kyoto/Okuyama.pdf
% income group factors for income groups 1-4, as well as missing data (5)
income_group_factor(1) = 0.9;
income_group_factor(2) = 0.4;
income_group_factor(3) = 0.5;
income_group_factor(4) = 1;
income_group_factor(5) = 0.4;   % default value for NaN entries
%
% insurance penetration factors
insurance_penetration_factor(1) = 0;    % insurance penetration <5%
insurance_penetration_factor(2) = 0.5;  % insurance penetration between 5% and 10%
insurance_penetration_factor(3) = 1;    % insurance penetration >10%
insurance_penetration_factor(4) = 0;    % default value for NaN entries
%
misdat_value = -999; %indicates missing data 
%
% If economic_data_file has not been passed as an input argument, look for
% default files (first for the standard file, and then for the extended
% file)
economic_data_file_default=[climada_global.data_dir filesep 'system' ...
    filesep 'economic_indicators_mastertable.xls'];
economic_data_file_default_extended=[climada_global.data_dir filesep 'system' ...
    filesep 'economic_indicators_mastertable_extended.xls'];
if isempty(economic_data_file)
    economic_data_file=economic_data_file_default;
    if exist(economic_data_file_default_extended,'file')
        economic_data_file=economic_data_file_default_extended;
    end
end

% The third option is to prompt for the file if neither the standard nor
% the extended default file exists, or if the file that has been passed as 
% an input does not exist
if ~exist(economic_data_file,'file')
    [filename, pathname] = uigetfile(economic_data_file_default,...
        'Choose the database containing the economic indicators:');
    if isequal(filename,0) || isequal(pathname,0)
        fprintf('No database selected, aborted\n');
        return; % cancel
    else
        economic_data_file=fullfile(pathname,filename);
    end
end

if ~exist(economic_data_file,'file'),fprintf('ERROR: file %s not found\n',economic_data_file);return;end

[~,economic_datafile_name,ext] = fileparts(economic_data_file);

%% read excel sheet with the (socio-)economic data needed in the calculation
master_data = climada_xlsread('no',economic_data_file,[],1,misdat_value);

% this part of the code was only used before climada_xlsread was able to
% directly replace missing data by NaN when reading the file
% replace -999 by NaN in the numeric data (which starts at the 4th column
% of master_data, after the fields 'filename', 'ISO3', and 'Country')
% fields = fieldnames(master_data);
% for i = 4 : numel(fields)
%     column_i = master_data.(fields{i});
%     no_data_indices = find(column_i == -999);
%     column_i(no_data_indices) = NaN;
%     master_data.(fields{i}) = column_i;
% end

% some parameters need to be converted into another unit
master_data.income_group(master_data.income_group==1)       = income_group_factor(1);
master_data.income_group(master_data.income_group==2)       = income_group_factor(2);
master_data.income_group(master_data.income_group==3)       = income_group_factor(3);
master_data.income_group(master_data.income_group==4)       = income_group_factor(4);
master_data.income_group(isnan(master_data.income_group))   = income_group_factor(5);

master_data.insurance_penetration(master_data.insurance_penetration <=5) = ...
    insurance_penetration_factor(1); 
master_data.insurance_penetration(master_data.insurance_penetration >5 & master_data.insurance_penetration <=10) = ...
    insurance_penetration_factor(2); 
master_data.insurance_penetration(master_data.insurance_penetration >10) = ...
    insurance_penetration_factor(3); 
master_data.insurance_penetration(isnan(master_data.insurance_penetration)) = ...
    insurance_penetration_factor(4); 

%% Check whether country_risk contains multiple countries, and if so, call
% climada_calculate_economic_loss recursively for each country
if length(country_risk)>1 % more than one country, process recursively
    n_countries=length(country_risk);
    for country_i = 1:n_countries
        %fprintf('round %d\n',country_i)
        single_country_name = country_risk(country_i).res.country_name;
        fprintf('\nprocessing %s (%i of %i) ************************ \n',...
            char(single_country_name),country_i,n_countries);
        country_risk_out=cr_economic_loss_calc(...
            country_risk(country_i), economic_data_file);
        country_risk_economic_loss(country_i) = country_risk_out;
    end   
    return;
end

%% From here on, only one country
% Check whether the country matches an entry in the Climada reference
% country list
country_name_char = char(country_risk.res.country_name);
[country_name_char_checked,country_ISO3] = climada_country_name(country_name_char); % check name and ISO3
if isempty(country_name_char_checked)
    fprintf('Warning: Unorthodox country name, check results. ');
else
    fprintf('Country name check successful: %s, ISO3 Code: %s. ', ...
            country_name_char_checked, country_ISO3);
end
if nnz(strcmp(master_data.Country,country_name_char)) ==0
    fprintf(['Error: %s not found in %s.%s. \n', ...
            'Please make sure that all country names match the Climada', ...
            'reference names. \n Type \"climada_country_name\" to see', ...
            'a list of all valid country names and their ISO3 codes. \n'], ...
            country_name_char, economic_datafile_name,ext)
    return;
else
    % Index in master_data where the data on country_name is to be found
    country_index = find(strcmp(master_data.Country,country_name_char));
end

%% calculate financial_strength, BI_and_supply_chain_risk, 
% natural_hazard_economic_exposure, and disaster_resilience based on the 
% data in master_data
fprintf('Calculating economic loss ...\n');
financial_strength = ...
    min(master_data.total_reserves(country_index)/master_data.GDP_today(country_index),1) ...% setting an upper bound of 1 
    + master_data.insurance_penetration(country_index) ...
    + master_data.income_group(country_index) ...
    - master_data.central_government_debt(country_index);
% make sure 1/financial_strength (i.e. the term that goes into the
% calculation of the country damage factor) does not exceed 2
if financial_strength < 0.5, financial_strength =0.5;end 
if isnan(financial_strength)
    fprintf(['Error: Missing data - could not calculate financial_strength ',...
            'of %s.\n',country_name_char]);
    fprintf(['Please make sure %s.%s contains data on GDP, total reserves, ',... 
            'insurance penetration, income group and central government ',...
            'of %s.\n'],economic_datafile_name,ext,country_name_char);
    return;
else
    fprintf('Financial strength: %6.3f\n',financial_strength);
end
BI_and_supply_chain_risk = ...
    master_data.GDP_industry(country_index) ...
    + (1-master_data.FM_resilience_index_supply_chain(country_index)/100);
if isnan(BI_and_supply_chain_risk)
    fprintf(['Error: Missing data - could not calculate BI_and_supply_chain_risk ',...
            'of %s.\n'],country_name_char);
    fprintf(['Please make sure %s.%s contains data on the share of GDP ' ,...
            'generated by the industrial sector, as well as the supply ' ,...
            ' chain factor of the FM Global Resilience Index of %s.\n'],...
            economic_datafile_name,ext,country_name_char);
    return;
else
    fprintf('Business interruption and supply chain risk: %6.3f\n',...
            BI_and_supply_chain_risk);
end

% Natural hazard exonomic exposure can only be calculated if the extended
% version of the economic indicators mastertable is used.
if isfield(master_data,'Natural_Hazard_Economic_Exposure')
    natural_hazard_economic_exposure = ...
        1-master_data.Natural_Hazards_Economic_Exposure(country_index)/10;
    if isnan(natural_hazard_economic_exposure)
        fprintf(['Error: Missing data - could not calculate natural_hazard_economic_exposure ',...
            'of %s.\n'],country_name_char);
        fprintf(['Please make sure %s.%s contains data on the Natural ',... 
            'Hazards Economic Exposure Index of %s.\n'],...
             economic_datafile_name,ext,country_name_char);
        return;
    else
        fprintf('Natural hazard economic exposure: %6.3f\n',natural_hazard_economic_exposure);
    end % isnan
else
    % natural hazard economic exposure won't be included in the calculation
    % of the country damage factor
    natural_hazard_economic_exposure = 0; 
end % isfield

disaster_resilience = ...
    master_data.FM_resilience_index_risk_quality(country_index)/100 ...
    + (master_data.global_competitiveness_index(country_index)-1)/6;
if isnan(disaster_resilience)
    fprintf(['Error: Missing data - could not calculate natural_hazard_economic_exposure ',...
            'of %s.\n'],country_name_char);
    fprintf(['Please make sure %s.%s contains data on the risk quality',...
            ' factor of the FM Global Resilience Index and the Global ',...
            ' Competitiveness Index of %s.\n'],...
            economic_datafile_name,ext,country_name_char);
    return;
else
    fprintf('Disaster resilience: %6.3f\n',disaster_resilience);
end

country_damage_factor = 1/financial_strength ...
    + BI_and_supply_chain_risk ...
    + natural_hazard_economic_exposure ...
    - disaster_resilience;
if country_damage_factor < 0, country_damage_factor = 0; end
fprintf('Country damage factor: %6.3f\n',country_damage_factor);


%% damage weight
% country_damage_factor will be multiplied by a damage weight that depends
% on damage(event_i)/GDP caused by the respective event.

% overwrite damage with economic loss according to
% economic_loss = damage * (1+loss_multiplier), where loss_multiplier is
% the product of the damage weight (calculated by the function
% get_damage_weight) and country_damage_factor

if isfield(country_risk.res,'hazard')
    for EDS_i = 1:length(country_risk.res.hazard)
        if ~isempty(country_risk.res.hazard(EDS_i).EDS)
            for damage_j = 1:length(country_risk.res.hazard(EDS_i).EDS.damage)
                damage_per_GDP = country_risk.res.hazard(EDS_i).EDS.damage(damage_j)/master_data.GDP_today(country_index);
                loss_multiplier = 1+cr_get_damage_weight(damage_per_GDP) * country_damage_factor;
                country_risk_economic_loss.res.hazard(EDS_i).EDS.damage(damage_j) = ...
                    country_risk.res.hazard(EDS_i).EDS.damage(damage_j) * loss_multiplier;
            end
        else
            country_risk_economic_loss.res.hazard(EDS_i).EDS = [];
        end
    end
end

