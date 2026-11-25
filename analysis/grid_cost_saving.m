%GRID_COST_SAVING  Grid Cost Saving (GCS) for every strategy, from saved results.
%
%   GCS = (E_baseline - E_strategy) * C_grid                       % Eq. 3.39
%
%   E_baseline : energy used by Strategy 1 (baseline) for the SAME season
%                and HVAC type, over the evaluation window (kWh)
%   E_strategy : energy used by the strategy being assessed (kWh)
%   C_grid     : grid electricity tariff, p.C_grid in sim_params.m
%                (NGN 250/kWh, NERC Band A)
%
%   This is the grid-supply counterpart of the Fuel-Cost Saving (FCS) that
%   metrics.m computes for generator supply: same energy difference, priced
%   at the grid tariff instead of diesel.
%
%   Eq. 3.39 in the report defines E_opt as the hybrid strategy (Strategy 3).
%   The same formula is applied here to the scheduled strategy as well, so it
%   can be compared with FCS, which metrics.m reports for both strategies.
%
%   Input : results/tables/metrics_combined.csv   (written by run_simulation.m)
%   Output: results/tables/grid_cost_saving.csv
%
%   Usage (from the repository root, after run_simulation):
%     >> grid_cost_saving

clear; clc;

in_csv  = 'results/tables/metrics_combined.csv';
out_csv = 'results/tables/grid_cost_saving.csv';

if ~exist(in_csv, 'file')
    error('grid_cost_saving:noResults', ...
        '%s not found. Run run_simulation.m first, from the repository root.', in_csv);
end

p      = sim_params('hot');      % C_grid is season-independent
C_grid = p.C_grid;               % NGN/kWh

T = readtable(in_csv, 'TextType', 'string');
T.GCS_NGN = zeros(height(T), 1);

for i = 1:height(T)
    is_base = T.HVAC_Type == T.HVAC_Type(i) & ...
              T.Season    == T.Season(i)    & ...
              T.Strategy  == "baseline";
    if nnz(is_base) ~= 1
        error('grid_cost_saving:baseline', ...
            'Expected exactly one baseline row for %s / %s, found %d.', ...
            T.HVAC_Type(i), T.Season(i), nnz(is_base));
    end
    E_base       = T.E_kWh(is_base);
    T.GCS_NGN(i) = (E_base - T.E_kWh(i)) * C_grid;     % Eq. 3.39 (0 for baseline)
end

out = T(:, {'HVAC_Type','Season','Strategy','E_kWh','FCS_NGN','GCS_NGN'});
writetable(out, out_csv);

fprintf('\n========= GRID COST SAVING (tariff = NGN %.2f/kWh) =========\n', C_grid);
fprintf(' %-9s %-5s %-10s %10s %14s %14s\n', 'HVAC', 'Season', 'Strategy', 'E (kWh)', 'FCS (NGN)', 'GCS (NGN)');
for i = 1:height(out)
    fprintf(' %-9s %-5s %-10s %10.4f %14.2f %14.2f\n', out.HVAC_Type(i), out.Season(i), ...
        out.Strategy(i), out.E_kWh(i), out.FCS_NGN(i), out.GCS_NGN(i));
end
fprintf('\n>> Written to %s\n\n', out_csv);
