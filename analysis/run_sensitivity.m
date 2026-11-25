%RUN_SENSITIVITY  Robustness sweep on the three most uncertain params.
%
% For each (parameter, level) combination, perturbs ONLY that parameter and
% re-runs the full paired experiment (3 strategies x 2 seasons) on the same
% seeded occupancy. Reports how the hybrid's headline numbers (ESI, TCSR)
% move under each perturbation.
%
% Sweeps:
%   C_th    : nominal +/- 50%   (thermal mass)
%   U_comp  : nominal +/- 20%   (envelope conductance)
%   COP_nom : nominal +/- 15%   (rated cooling efficiency)
%
% Pass criterion (robustness)
%   Hybrid ESI vs baseline stays POSITIVE in every variant of every season.
%   Hybrid TCSR stays higher than both conventional strategies in every variant.
%
% Outputs
%   results/tables/sensitivity_<season>.csv
%   results/tables/sensitivity_summary.csv
%   results/figures/sensitivity_<season>.png

clear; clc; close all;

% --------- parameter sweeps ----------
sweeps(1).name = 'C_th';     sweeps(1).deltas = [-0.50, 0.00, +0.50];
sweeps(2).name = 'U_comp';   sweeps(2).deltas = [-0.20, 0.00, +0.20];
sweeps(3).name = 'COP_nom';  sweeps(3).deltas = [-0.15, 0.00, +0.15];

seasons = {'hot','rain'};
strats  = {'baseline','scheduled','hybrid'};

% --------- generate occupancy ONCE (same inputs for every run) ----------
p_ref = sim_params('hot');
[N_occ, ~] = occupancy_profile(p_ref);

% --------- storage ----------
rows = {};      % cell array of struct rows for the summary table

fprintf('\n========== SENSITIVITY SWEEP (3 params x 3 levels x 2 seasons) ==========\n');

for si = 1:numel(sweeps)
    pname  = sweeps(si).name;
    deltas = sweeps(si).deltas;

    for di = 1:numel(deltas)
        d = deltas(di);

        for sn = 1:numel(seasons)
            season = seasons{sn};

            % --- build perturbed params ---
            p = sim_params(season);
            nominal = p.(pname);
            p.(pname) = nominal * (1 + d);

            % --- recompute weather (season-dependent, param-independent) ---
            T_out = weather_profile(p);

            % --- run all 3 strategies ---
            log_b = strategy_baseline (T_out, N_occ, p);
            log_s = strategy_scheduled(T_out, N_occ, p);
            log_h = strategy_hybrid   (T_out, N_occ, p);

            % --- metrics with baseline anchor ---
            m_b0 = metrics(log_b, p);
            E_base = m_b0.E_kWh;
            m_b = metrics(log_b, p, E_base);
            m_s = metrics(log_s, p, E_base);
            m_h = metrics(log_h, p, E_base);

            % --- store one row per strategy ---
            for st = 1:numel(strats)
                strat = strats{st};
                switch strat
                    case 'baseline',  m = m_b;
                    case 'scheduled', m = m_s;
                    case 'hybrid',    m = m_h;
                end
                r.param   = pname;
                r.delta   = d;
                r.value   = p.(pname);
                r.season  = season;
                r.strategy= strat;
                r.E_kWh   = m.E_kWh;
                r.ESI     = m.ESI;
                r.TCSR    = m.TCSR;
                r.MTD     = m.MTD;
                r.FCS_NGN = m.FCS_NGN;
                rows{end+1} = r;                  %#ok<SAGROW>
            end

            fprintf('  %-8s d=%+5.0f%%  %5s : hybrid ESI=%+6.2f%%  TCSR=%6.2f%%\n', ...
                pname, 100*d, season, m_h.ESI, m_h.TCSR);
        end
    end
end

% --------- write summary CSV ----------
if ~exist('results/tables','dir'), mkdir('results/tables'); end
fid = fopen('results/tables/sensitivity_summary.csv','w');
fprintf(fid,'Parameter,DeltaPct,Value,Season,Strategy,E_kWh,ESI_pct,TCSR_pct,MTD_degC,FCS_NGN\n');
for i = 1:numel(rows)
    r = rows{i};
    fprintf(fid,'%s,%.1f,%.4f,%s,%s,%.4f,%.4f,%.4f,%.4f,%.2f\n', ...
        r.param, 100*r.delta, r.value, r.season, r.strategy, ...
        r.E_kWh, r.ESI, r.TCSR, r.MTD, r.FCS_NGN);
end
fclose(fid);

% --------- per-season summary tables ----------
for sn = 1:numel(seasons)
    season = seasons{sn};
    fid = fopen(sprintf('results/tables/sensitivity_%s.csv', season),'w');
    fprintf(fid,'Parameter,DeltaPct,Hybrid_E_kWh,Hybrid_ESI_pct,Hybrid_TCSR_pct,Baseline_E_kWh,Scheduled_E_kWh,Scheduled_ESI_pct\n');
    for i = 1:numel(rows)
        if ~strcmp(rows{i}.season, season) || ~strcmp(rows{i}.strategy,'hybrid'), continue; end
        h = rows{i};
        % find matching baseline & scheduled rows
        b = find_row(rows, h.param, h.delta, season, 'baseline');
        s = find_row(rows, h.param, h.delta, season, 'scheduled');
        fprintf(fid,'%s,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n', ...
            h.param, 100*h.delta, h.E_kWh, h.ESI, h.TCSR, b.E_kWh, s.E_kWh, s.ESI);
    end
    fclose(fid);
end

% --------- pretty per-season console table ----------
for sn = 1:numel(seasons)
    season = seasons{sn};
    fprintf('\n=============== SENSITIVITY  --  %s season  (HYBRID rows) ===============\n', upper(season));
    fprintf('  %-8s | %6s | %8s | %8s | %10s\n','Param','Delta%','E (kWh)','ESI %','TCSR %');
    fprintf('  %s\n', repmat('-',1,52));
    for si = 1:numel(sweeps)
        for di = 1:numel(sweeps(si).deltas)
            d = sweeps(si).deltas(di);
            h = find_row(rows, sweeps(si).name, d, season, 'hybrid');
            fprintf('  %-8s | %+5.0f%% | %8.2f | %+7.2f | %9.2f\n', ...
                sweeps(si).name, 100*d, h.E_kWh, h.ESI, h.TCSR);
        end
    end
end

% --------- robustness verdict ----------
fprintf('\n=============== ROBUSTNESS VERDICT ===============\n');
all_pos = true; all_comf = true;
for i = 1:numel(rows)
    if ~strcmp(rows{i}.strategy,'hybrid'), continue; end
    if rows{i}.ESI <= 0
        all_pos = false;
        fprintf('  WARN: hybrid ESI non-positive at %s d=%+.0f%% (%s) : %.2f%%\n', ...
            rows{i}.param, 100*rows{i}.delta, rows{i}.season, rows{i}.ESI);
    end
end
% comfort: hybrid TCSR >= max(baseline,scheduled) in every variant
for si = 1:numel(sweeps)
    for di = 1:numel(sweeps(si).deltas)
        d = sweeps(si).deltas(di);
        for sn = 1:numel(seasons)
            season = seasons{sn};
            h = find_row(rows, sweeps(si).name, d, season, 'hybrid');
            b = find_row(rows, sweeps(si).name, d, season, 'baseline');
            s = find_row(rows, sweeps(si).name, d, season, 'scheduled');
            if h.TCSR < max(b.TCSR, s.TCSR)
                all_comf = false;
                fprintf('  WARN: hybrid TCSR not best at %s d=%+.0f%% (%s)\n', ...
                    sweeps(si).name, 100*d, season);
            end
        end
    end
end
if all_pos,  fprintf('  Hybrid ESI > 0 in EVERY variant : PASS\n'); end
if all_comf, fprintf('  Hybrid TCSR best-in-class in EVERY variant : PASS\n'); end

% --------- bar-chart figures per season ----------
if ~exist('results/figures','dir'), mkdir('results/figures'); end
for sn = 1:numel(seasons)
    season = seasons{sn};
    fig = figure('Position',[40 40 1200 400], 'Visible','off');

    for si = 1:numel(sweeps)
        subplot(1,3,si);
        ds = sweeps(si).deltas;
        esis  = arrayfun(@(d) find_row(rows, sweeps(si).name, d, season,'hybrid').ESI,  ds);
        tcsrs = arrayfun(@(d) find_row(rows, sweeps(si).name, d, season,'hybrid').TCSR, ds);
        yyaxis left;  bar(100*ds, esis);  ylabel('Hybrid ESI (%)');
        yyaxis right; plot(100*ds, tcsrs,'r-o','LineWidth',1.5); ylabel('Hybrid TCSR (%)');
        xlabel(sprintf('%s deviation (%%)', sweeps(si).name));
        title(sweeps(si).name); grid on;
    end
    sgtitle(sprintf('Sensitivity sweep  --  %s season', upper(season)));
    savefig(fig, sprintf('results/figures/sensitivity_%s.fig', season));
    exportgraphics(fig, sprintf('results/figures/sensitivity_%s.png', season),'Resolution',150);
    close(fig);
end

fprintf('\n>> Sensitivity tables in results/tables/   Figures in results/figures/\n\n');

% ============ helper ============
function r = find_row(rows, param, delta, season, strategy)
    for i = 1:numel(rows)
        if strcmp(rows{i}.param,param) && abs(rows{i}.delta-delta)<1e-9 ...
                && strcmp(rows{i}.season,season) && strcmp(rows{i}.strategy,strategy)
            r = rows{i}; return;
        end
    end
    r = struct('E_kWh',NaN,'ESI',NaN,'TCSR',NaN,'MTD',NaN,'FCS_NGN',NaN);
end
