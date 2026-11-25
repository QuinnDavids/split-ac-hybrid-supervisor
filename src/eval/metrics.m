function m = metrics(log, p, E_baseline_kWh)
%METRICS  Compute Chapter-3 performance metrics on the evaluation window.
%   m = METRICS(log, p)                       -- ESI/FCS set to NaN
%   m = METRICS(log, p, E_baseline_kWh)       -- ESI/FCS computed
%
%   Window
%     Days 1 .. p.learn_days   -> EXCLUDED (Strategy-3 warm-up; never test on training data)
%     Days p.learn_days+1 .. p.days -> EVALUATION (same window for all 3 strategies)
%
%   Outputs (struct)
%     m.E_kWh    Total electrical energy consumed in window           (Eq. 3.33)
%     m.ESI      Energy-Saving Index vs E_baseline_kWh, in percent    (Eq. 3.35)
%     m.TCSR     Thermal Comfort Satisfaction Rate, in percent        (Eq. 3.36)
%                = 100 * (# occupied steps in [T_min, T_max]) / (# occupied steps)
%     m.MTD      Mean Temperature Deviation from set-point during     (Eq. 3.37)
%                occupied steps (degC)
%     m.FCS_NGN  Fuel-Cost Saving in NGN over the evaluation window,  (Eq. 3.38)
%                diesel genset basis (window length = p.days - p.learn_days)
%                E_saved_L = (E_base - E_strategy) / (eta_gen * CV_diesel)
%                FCS_NGN   = E_saved_L * C_diesel
%     m.duty     Compressor duty cycle in window (% on)
%     m.occ_hrs  Occupied hours in window (h)
%     m.eval_window  [start_step, end_step] indices

    steps_per_day = 24 * 3600 / p.dt;
    eval_start    = p.learn_days * steps_per_day + 1;
    eval_end      = p.N;
    idx           = (eval_start : eval_end).';
    m.eval_window = [eval_start, eval_end];

    % --- Energy (kWh, Eq. 3.33) ---
    m.E_kWh = sum(log.P_elec(idx)) * p.dt / 3.6e6;

    % --- Duty / occupied hours diagnostics ---
    m.duty    = 100 * mean(log.is_on(idx));
    m.occ_hrs = sum(log.N_occ(idx) > 0) * p.dt / 3600;

    % --- TCSR (Eq. 3.36) ---
    occ      = log.N_occ(idx) > 0;
    in_band  = (log.T_in(idx) >= p.T_min) & (log.T_in(idx) <= p.T_max);
    n_occ    = sum(occ);
    if n_occ > 0
        m.TCSR = 100 * sum(occ & in_band) / n_occ;
    else
        m.TCSR = NaN;
    end

    % --- MTD (Eq. 3.37) ---
    % Deviation from the COMMANDED set-point during occupied periods.
    % Use only steps where the AC was commanded ON (Strategy 1/2 OFF periods
    % carry a stale T_set placeholder we don't want to skew the metric).
    if isfield(log, 'ac_on')
        valid = occ & log.ac_on(idx);
    else
        % Strategies 1/2: AC commanded on when is_on is meaningful;
        % use occ & |T_set - 22..30| range to filter sentinels.
        % Revision note: widened from [22,28] to [22,30] so this still
        % covers every REAL setpoint used by any strategy (18/22 baseline,
        % 22 scheduled, 23-27 hybrid, 30 hybrid setback) under the new
        % comfort band -- this is a sentinel-filter fix, not a change to
        % what any strategy actually targets. The 18C baseline overcool
        % phase remains deliberately excluded.
        sane_setpoint = log.T_set(idx) >= 22 & log.T_set(idx) <= 30;
        valid = occ & sane_setpoint;
    end
    if any(valid)
        dev = abs(log.T_in(idx) - log.T_set(idx));
        m.MTD = mean(dev(valid));
    else
        m.MTD = NaN;
    end

    % --- ESI & FCS (Eq. 3.35 & 3.38) ---
    if nargin >= 3 && ~isnan(E_baseline_kWh) && E_baseline_kWh > 0
        m.ESI     = 100 * (E_baseline_kWh - m.E_kWh) / E_baseline_kWh;
        E_saved_L = (E_baseline_kWh - m.E_kWh) / (p.eta_gen * p.CV_diesel);
        m.FCS_NGN = E_saved_L * p.C_diesel;
    else
        m.ESI     = NaN;
        m.FCS_NGN = NaN;
    end
end
