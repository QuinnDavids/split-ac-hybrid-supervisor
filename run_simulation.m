%RUN_SIMULATION  Full paired experiment: 2 HVAC types x 3 strategies x 2 seasons.
%
% Run matrix: the original 3-strategies x 2-seasons (6 runs) matrix is
% extended to ALSO sweep HVAC compressor type (12 runs total).
% Implemented as a nested loop in this SAME script (not a parallel
% run_simulation_bangbang.m) so metrics/plotting/CSV export logic is not
% duplicated.
%
%   - Hot-dry  (Harmattan)  : sim_params('hot')
%   - Rainy    (Monsoon)    : sim_params('rain')
%   - Inverter               : p.hvac_type = 'inverter' (modulating, Eq.3.26-3.27)
%   - Bang-bang               : p.hvac_type = 'bangbang' (fixed-speed, binary ON/OFF)
%
% For each (hvac_type, season) pair, runs Strategy 1 (baseline), Strategy 2
% (scheduled), Strategy 3 (hybrid) on byte-identical boundary conditions:
%   * weather   : season-specific (different by design)
%   * occupancy : SAME realised array across ALL seasons AND hvac types
%                 (fair comparison: identical inputs) -- the RNG streams inside
%                 strategy_baseline.m / strategy_hybrid.m are reseeded from
%                 p.seed at the start of every call regardless of hvac_type,
%                 so the coin-flip/occupancy-driven decisions are identical
%                 across hvac types; only the PHYSICS response differs.
%
% Metrics are computed on the evaluation window only (days p.learn_days+1
% .. p.days) using metrics.m, with EACH hvac_type's strategies anchored to
% THAT hvac_type's own baseline E_kWh (apples-to-apples ESI within a
% compressor type; E_kWh and ESI can still be compared side-by-side ACROSS
% hvac types since both are absolute/relative energy measures).
%
% Results struct: R.(hvac_type).(season).(strategy).log/.m
%   -- generate_html_report.m auto-detects this nesting and renders a
%      separate figure section per HVAC type (design choice: keeps figures readable).
%
% Outputs to results/tables/:
%   metrics_<season>_<hvac>.csv, metrics_combined.csv (now carries an
%   HVAC_Type column)
% And to results/figures/:
%   week_<season>_<hvac>.png : indoor-T traces + power for each strategy
%   bars_<season>_<hvac>.png : energy / TCSR / ESI bar chart
%   baseline_leaveon_log.txt : per-day baseline coin outcomes -- HVAC-type
%     INDEPENDENT (occupancy/coin RNG doesn't depend on hvac_type), so
%     written once, not duplicated per hvac_type.

clear; clc; close all;

hvac_types = {'inverter','bangbang'};
seasons    = {'hot','rain'};
strats     = {'baseline','scheduled','hybrid'};

% ---- 1. Generate the ONE occupancy realisation reused across EVERYTHING ----
% (season-independent AND hvac-type-independent -- same inputs for a fair comparison)
p_ref = sim_params('hot');                 % season-independent fields
[N_occ, occ_bool] = occupancy_profile(p_ref);

% ---- 2. Storage ----
R = struct();                              % R.(hvac_type).(season).(strategy).log/m

% ---- 3. Run experiments ----
fprintf('\n===== RUNNING PAIRED EXPERIMENT (2 HVAC types x 3 strategies x 2 seasons = 12 runs) =====\n');
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    fprintf('\n########## HVAC type: %s ##########\n', upper(hvac));

    for s = 1:numel(seasons)
        season = seasons{s};
        p      = sim_params(season);
        p.hvac_type = hvac;                % select compressor model for this run
        T_out  = weather_profile(p);
        fprintf('\n--- Season: %s   (T_avg=%.1f, T_amp=%.1f, solar=%.2f, latent=%d, hvac=%s) ---\n', ...
            season, p.T_avg, p.T_amp, p.solar_factor, p.use_latent, hvac);

        for st = 1:numel(strats)
            strat = strats{st};
            tic;
            switch strat
                case 'baseline',  log = strategy_baseline (T_out, N_occ, p);
                case 'scheduled', log = strategy_scheduled(T_out, N_occ, p);
                case 'hybrid',    log = strategy_hybrid   (T_out, N_occ, p);
            end
            dt_run = toc;
            R.(hvac).(season).(strat).log = log;
            fprintf('  %-10s  done in %.2f s\n', strat, dt_run);
        end

        % --- compute metrics: baseline first, then others using ITS OWN
        %     hvac_type's E_kWh as the anchor (not shared across hvac types) ---
        m_base = metrics(R.(hvac).(season).baseline.log, p);
        E_base = m_base.E_kWh;
        R.(hvac).(season).baseline.m  = metrics(R.(hvac).(season).baseline.log,  p, E_base);
        R.(hvac).(season).scheduled.m = metrics(R.(hvac).(season).scheduled.log, p, E_base);
        R.(hvac).(season).hybrid.m    = metrics(R.(hvac).(season).hybrid.log,    p, E_base);
    end
end

% ---- 4. Print per-hvac-type, per-season tables ----
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    for s = 1:numel(seasons)
        season = seasons{s};
        fprintf('\n========= METRICS -- %s season, %s HVAC (days %d-%d) =========\n', ...
            upper(season), upper(hvac), p_ref.learn_days+1, p_ref.days);
        fprintf('  %-10s | %8s | %8s | %8s | %8s | %10s | %7s\n', ...
            'Strategy','E (kWh)','ESI (%)','TCSR (%)','MTD (degC)','FCS (NGN)','Duty %');
        fprintf('  %s\n', repmat('-',1,82));
        for st = 1:numel(strats)
            strat = strats{st};
            m = R.(hvac).(season).(strat).m;
            fprintf('  %-10s | %8.2f | %8.2f | %8.2f | %8.2f | %10.0f | %7.2f\n', ...
                strat, m.E_kWh, m.ESI, m.TCSR, m.MTD, m.FCS_NGN, m.duty);
        end
    end
end

% ---- 5. Cross-season contrast per HVAC type (seasonal comparison questions Q1-Q3) ----
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    fprintf('\n========= CROSS-SEASON CONTRAST -- %s HVAC (Sec 6.5 Q1-Q3) =========\n', upper(hvac));
    fprintf(' Q1: Does hybrid hold comfort AND save energy in BOTH seasons?\n');
    for s = 1:numel(seasons)
        season = seasons{s};
        m = R.(hvac).(season).hybrid.m;
        fprintf('     %5s : ESI = %+5.2f%%   TCSR = %5.2f%%\n', season, m.ESI, m.TCSR);
    end
    fprintf('\n Q2: In which season is the framework MORE energy-efficient (higher ESI)?\n');
    esi_hot  = R.(hvac).hot.hybrid.m.ESI;
    esi_rain = R.(hvac).rain.hybrid.m.ESI;
    if esi_hot > esi_rain
        fprintf('     => HOT-DRY  (ESI %.2f%% vs %.2f%%)\n', esi_hot, esi_rain);
    else
        fprintf('     => RAINY    (ESI %.2f%% vs %.2f%%)\n', esi_rain, esi_hot);
    end
    fprintf('\n Q3: In which season does CONVENTIONAL control waste the most energy?\n');
    for s = 1:numel(seasons)
        season = seasons{s};
        fprintf('     %5s baseline : %6.2f kWh   scheduled : %6.2f kWh\n', ...
            season, R.(hvac).(season).baseline.m.E_kWh, R.(hvac).(season).scheduled.m.E_kWh);
    end
end

% ---- 5b. Inverter vs Bang-bang headline comparison ----
fprintf('\n========= INVERTER vs BANG-BANG -- hybrid ESI headline =========\n');
for s = 1:numel(seasons)
    season = seasons{s};
    esi_inv = R.inverter.(season).hybrid.m.ESI;
    esi_bb  = R.bangbang.(season).hybrid.m.ESI;
    winner  = ternary(esi_inv >= esi_bb, 'INVERTER', 'BANGBANG');
    fprintf('     %5s : inverter ESI = %+6.2f%%   bangbang ESI = %+6.2f%%   -> %s better\n', ...
        season, esi_inv, esi_bb, winner);
end

% ---- 6. Save CSV tables ----
if ~exist('results/tables','dir'), mkdir('results/tables'); end
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    for s = 1:numel(seasons)
        season = seasons{s};
        fname = sprintf('results/tables/metrics_%s_%s.csv', season, hvac);
        fid = fopen(fname,'w');
        fprintf(fid,'Strategy,E_kWh,ESI_pct,TCSR_pct,MTD_degC,FCS_NGN,Duty_pct,OccupiedHours\n');
        for st = 1:numel(strats)
            strat = strats{st};
            m = R.(hvac).(season).(strat).m;
            fprintf(fid,'%s,%.4f,%.4f,%.4f,%.4f,%.2f,%.4f,%.2f\n', ...
                strat, m.E_kWh, m.ESI, m.TCSR, m.MTD, m.FCS_NGN, m.duty, m.occ_hrs);
        end
        fclose(fid);
    end
end
% combined long-form -- carries an HVAC_Type column
fid = fopen('results/tables/metrics_combined.csv','w');
fprintf(fid,'HVAC_Type,Season,Strategy,E_kWh,ESI_pct,TCSR_pct,MTD_degC,FCS_NGN,Duty_pct,OccupiedHours\n');
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    for s = 1:numel(seasons)
        for st = 1:numel(strats)
            m = R.(hvac).(seasons{s}).(strats{st}).m;
            fprintf(fid,'%s,%s,%s,%.4f,%.4f,%.4f,%.4f,%.2f,%.4f,%.2f\n', ...
                hvac, seasons{s}, strats{st}, m.E_kWh, m.ESI, m.TCSR, m.MTD, m.FCS_NGN, m.duty, m.occ_hrs);
        end
    end
end
fclose(fid);

% ---- 7. Baseline leave-on coin outcomes (HVAC-type INDEPENDENT) ----
% Occupancy/coin-flip RNG in strategy_baseline.m is reseeded from p.seed
% every call regardless of hvac_type, so these outcomes are IDENTICAL for
% inverter and bangbang -- written once using the inverter run to avoid a
% duplicate, byte-identical file.
fid = fopen('results/tables/baseline_leaveon_log.txt','w');
fprintf(fid,'BASELINE leave-on coin outcomes (seed = %d, prob = %.2f)\n', ...
    p_ref.seed, p_ref.base_leaveon_prob);
fprintf(fid,'NOTE: identical for every HVAC type -- occupancy/coin RNG does not depend on p.hvac_type.\n\n');
steps_per_day = 24*3600/p_ref.dt;
for s = 1:numel(seasons)
    season = seasons{s};
    leave_on = R.inverter.(season).baseline.log.leave_on;
    fprintf(fid,'Season: %s\n', season);
    for d = 1:p_ref.days
        seg = leave_on((d-1)*steps_per_day + (1:min(steps_per_day, p_ref.N-(d-1)*steps_per_day)));
        hrs = sum(seg) * p_ref.dt/3600;
        if hrs > 0
            fprintf(fid,'  Day %d : leave-on  (%.1f hours)\n', d, hrs);
        else
            fprintf(fid,'  Day %d : OFF as normal\n', d);
        end
    end
    fprintf(fid,'\n');
end
fclose(fid);

% ---- 8. Plots: full-study trace per (season, hvac_type) ----
% NOTE: x-axis span, eval-window marker, etc. are all driven by p_ref.N and
% p_ref.learn_days, so this plot rescales automatically to whatever p.days /
% p.learn_days are set to in sim_params.m.
if ~exist('results/figures','dir'), mkdir('results/figures'); end
t_h = (0:p_ref.N-1).' * p_ref.dt / 3600;

for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    for s = 1:numel(seasons)
        season = seasons{s};
        fig = figure('Name', sprintf('%d-day trace -- %s -- %s', p_ref.days, season, hvac), ...
                     'Position',[40 40 1300 700], 'Visible','off');

        subplot(2,1,1);
        plot(t_h, R.(hvac).(season).baseline.log.T_out, 'k:', 'LineWidth', 0.8); hold on;
        plot(t_h, R.(hvac).(season).baseline.log.T_in,  'b-', 'LineWidth', 1.0);
        plot(t_h, R.(hvac).(season).scheduled.log.T_in, 'r-', 'LineWidth', 1.0);
        plot(t_h, R.(hvac).(season).hybrid.log.T_in,    'm-', 'LineWidth', 1.2);
        yline(sim_params(season).T_min,'g:'); yline(sim_params(season).T_max,'g:');
        xline(p_ref.learn_days*24,'k--','eval starts');
        xlabel('time (h)'); ylabel('T (degC)'); grid on;
        legend({'T_{out}','Baseline','Scheduled','Hybrid','comfort band'},'Location','best');
        title(sprintf('%d-day indoor temperature trace -- %s season (%s)', p_ref.days, upper(season), upper(hvac)));

        subplot(2,1,2);
        plot(t_h, R.(hvac).(season).baseline.log.P_elec, 'b-'); hold on;
        plot(t_h, R.(hvac).(season).scheduled.log.P_elec,'r-');
        plot(t_h, R.(hvac).(season).hybrid.log.P_elec,   'm-');
        xline(p_ref.learn_days*24,'k--');
        xlabel('time (h)'); ylabel('P_{elec} (W)'); grid on;
        legend({'Baseline','Scheduled','Hybrid'},'Location','best');
        title(sprintf('Electrical power draw (%s)', upper(hvac)));

        savefig(fig, sprintf('results/figures/week_%s_%s.fig', season, hvac));
        exportgraphics(fig, sprintf('results/figures/week_%s_%s.png', season, hvac), 'Resolution', 150);
        close(fig);
    end
end

% ---- 9. Bar chart per (season, hvac_type) ----
for h = 1:numel(hvac_types)
    hvac = hvac_types{h};
    for s = 1:numel(seasons)
        season = seasons{s};
        Es   = [R.(hvac).(season).baseline.m.E_kWh,  R.(hvac).(season).scheduled.m.E_kWh,  R.(hvac).(season).hybrid.m.E_kWh];
        ESIs = [R.(hvac).(season).baseline.m.ESI,    R.(hvac).(season).scheduled.m.ESI,    R.(hvac).(season).hybrid.m.ESI];
        TCSRs= [R.(hvac).(season).baseline.m.TCSR,   R.(hvac).(season).scheduled.m.TCSR,   R.(hvac).(season).hybrid.m.TCSR];

        fig = figure('Name', sprintf('Bars -- %s -- %s', season, hvac), ...
                     'Position',[40 40 1100 400], 'Visible','off');
        subplot(1,3,1); bar(Es);    set(gca,'XTickLabel',strats); ylabel('E (kWh)');    title('Energy (eval window)'); grid on;
        subplot(1,3,2); bar(ESIs);  set(gca,'XTickLabel',strats); ylabel('ESI (%)');   title('Energy Saving Index');   grid on;
        subplot(1,3,3); bar(TCSRs); set(gca,'XTickLabel',strats); ylabel('TCSR (%)');  title('Thermal Comfort Sat.');  grid on;
        sgtitle(sprintf('%s season (%s)', upper(season), upper(hvac)));
        savefig(fig, sprintf('results/figures/bars_%s_%s.fig', season, hvac));
        exportgraphics(fig, sprintf('results/figures/bars_%s_%s.png', season, hvac), 'Resolution', 150);
        close(fig);
    end
end

% ---- 10. Persist the full results struct for later analysis ----
if ~exist('results','dir'), mkdir('results'); end
save('results/run_simulation_results.mat', 'R', '-v7.3');

fprintf('\n>> Tables written to results/tables/   Figures to results/figures/   Full struct to results/run_simulation_results.mat\n');
fprintf('>> 12-run matrix complete (2 HVAC types x 3 strategies x 2 seasons).\n\n');

% ---------- helper ----------
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
