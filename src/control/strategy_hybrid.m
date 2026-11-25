function log = strategy_hybrid(T_out, N_occ, p)
%STRATEGY_HYBRID  Strategy 3 -- two-layer hybrid supervisory controller.
%   log = STRATEGY_HYBRID(T_out, N_occ, p)
%
%   Layer 1 (physics)  -- layer1_physics.m
%     Event-driven optimisation over S_cand = {23,24,25,26,27} degC
%     (Eq. 3.15) with a 30-minute forward-sim safety check (Eq. 3.4-3.5).
%     Cost  J = E_kWh + w_c * comfort_pen
%     Picks the candidate that minimises J subject to safety.
%
%   Layer 2 (learning) -- layer2_learning.m
%     Runs during the warm-up window (days 1 .. p.learn_days).
%     - Markov occupancy counts -> P(occupied | day_type, hour) for the
%       20-minute pre-cool trigger (Eq. 3.9-3.10).
%     - RLS calibration of U_comp from BTM residuals (Eq. 3.7-3.8).
%     - EMA preference tracking of T_in during occupied periods (Eq. 3.6).
%     Learners FREEZE at day p.learn_days + 1; the evaluation window
%     (days p.learn_days+1 .. p.days) uses the frozen parameters. This
%     ensures the controller is never tested on its training data.
%
%   Triggers for Layer-1 re-optimisation (§3.5.5)
%     T1. Temperature bound violation while occupied: T_in > T_max or
%         T_in < T_min. (Gated to occupied steps -- the unoccupied setback
%         of 30 degC is always above T_max by design, so an ungated check
%         would fire on every unoccupied step. This gating is an
%         implementation choice, not stated explicitly in the thesis text.)
%     T2. Occupancy state transition (arrival or departure).
%     T3. Thermal load change > 20% relative to the previous optimisation
%         cycle. Load is estimated each step as Q_env + Q_int + Q_sol
%         (mirrors Eqs. 3.18-3.21; computed locally here for comparison
%         only -- does NOT call or modify btm_step.m).
%     T4. Periodic refresh every OPT_PERIOD_MIN (15) minutes. This is
%         DELIBERATELY NOT the thesis's fixed-milestone version (06:00,
%         12:00, 18:00, 22:00) -- kept as the original 15-min refresh for
%         responsiveness/pre-cool support. T1-T3 are the thesis-matched
%         triggers; T4 is an intentional deviation, documented as such.
%
%   Unoccupied behaviour
%     - Setback to T_setback (30 degC) when room is empty (Eq. 3.13),
%       UNLESS the Markov predictor says P(occ in 20 min) >= p.P_occ_thr,
%       in which case AC pre-cools at T_pref (lower set-point).
%     - If even setback is unnecessary (room already cool), HEM stays off.

    rng(p.seed + 3);                              % isolate hybrid RNG stream
    steps_per_day    = 24 * 3600 / p.dt;
    OPT_PERIOD_MIN   = 15;                         % T4: periodic refresh (restored)
    OPT_PERIOD_STEPS = OPT_PERIOD_MIN * 60 / p.dt;
    LOAD_CHANGE_THR  = 0.20;                       % T3: 20% relative load change
    W_COMFORT        = 0.5;                        % cost weight: kWh vs degC^2*min
    LEARN_END_STEP   = p.learn_days * steps_per_day;

    % --- storage ---
    T_in       = zeros(p.N, 1);   T_in(1) = p.T_avg;
    T_set_log  = zeros(p.N, 1);
    P_elec_log = zeros(p.N, 1);
    Q_cool_log = zeros(p.N, 1);
    is_on_log  = false(p.N, 1);
    ac_on_log  = false(p.N, 1);
    f_mod_log  = zeros(p.N, 1);
    trigger_log = false(p.N, 1);
    U_est_log  = zeros(p.N, 1);
    Tpref_log  = zeros(p.N, 1);
    branch_log = strings(p.N, 1);                 % diagnostic: which decision branch fired

    % --- HEM state ---
    hem.is_on          = false;
    hem.t_since_change = p.dt_min;

    % --- Layer-2 learner state ---
    learn.U_est      = p.U_comp;                  % initialise at nominal
    learn.dT_sol_est = p.dT_sol;                  % (not actively updated; reserved)
    learn.T_pref     = (p.T_min + p.T_max) / 2;   % 25 degC midpoint
    learn.occ_counts = ones(7, 24, 2);            % start at 1 to avoid 0/0 (Laplace smoothing)

    % --- controller state ---
    T_set    = p.T_setback;
    ac_on    = false;
    prev_occ = false;
    last_opt_step    = -OPT_PERIOD_STEPS;
    load_at_last_opt = NaN;                       % T3 snapshot, set on first trigger
    last_branch      = "none";                    % diagnostic: which decision branch is active

    t_s      = (0:p.N-1).' * p.dt;
    t_hour   = mod(t_s/3600, 24);
    day_idx  = floor(t_s/86400) + 1;
    day_type = mod(day_idx - 1, 7) + 1;

    % --- main loop ---
    for k = 1:p.N-1
        cur_occ  = N_occ(k) > 0;
        cur_hour = t_hour(k);
        cur_day  = day_type(k);

        in_learn_phase = k <= LEARN_END_STEP;

        % ============ Layer 2: learn (days 1..p.learn_days only) ============
        if in_learn_phase && k > 1
            % Predict what BTM said T_in(k) should have been, using k-1 state
            T_pred_k = btm_step(T_in(k-1), T_out(k-1), N_occ(k-1), ...
                                Q_cool_log(k-1), t_hour(k-1), p);
            learn = layer2_learning(learn, T_in(k), T_pred_k, T_out(k-1), ...
                                    N_occ(k), cur_hour, cur_day, p);
        end

        % ============ Predict P(occupied 20 min ahead) ============
        future_hour = mod(cur_hour + p.precool_min/60, 24);
        future_bin  = min(24, max(1, floor(future_hour) + 1));
        c = squeeze(learn.occ_counts(cur_day, future_bin, :));
        if sum(c) > 0
            P_occ_future = c(2) / sum(c);
        else
            P_occ_future = 0.5;
        end

        % ============ Thermal load estimate (for T3 only) ============
        % Mirrors Eqs. 3.18-3.21. This is a LOCAL estimate for trigger
        % comparison only -- it does not call or modify btm_step.m, and
        % does not feed back into the physics.
        Q_env_now = p.U_comp * p.A_env * (T_out(k) - T_in(k));    % Eq. 3.18
        if p.use_latent
            Q_env_now = Q_env_now * (1 + p.f_lat);                % Eq. 3.19
        end
        Q_int_now = N_occ(k) * p.q_met + p.P_equip;               % Eq. 3.20
        if cur_hour >= 10 && cur_hour < 16
            Q_sol_now = p.solar_factor * p.U_comp * p.A_roof * p.dT_sol;  % Eq. 3.21
        else
            Q_sol_now = 0;
        end
        load_now = Q_env_now + Q_int_now + Q_sol_now;

        % ============ Trigger detection (§3.5.5, thesis-literal) ============
        trig = false;

        % T1: temperature bound violation while occupied
        if cur_occ && (T_in(k) > p.T_max || T_in(k) < p.T_min)
            trig = true;
        end

        % T2: occupancy state transition
        if cur_occ ~= prev_occ
            trig = true;
        end

        % T3: thermal load change > 20% vs. the previous optimisation cycle
        if ~isnan(load_at_last_opt) && abs(load_at_last_opt) > 1e-6
            rel_load_change = abs(load_now - load_at_last_opt) / abs(load_at_last_opt);
            if rel_load_change > LOAD_CHANGE_THR
                trig = true;
            end
        end

        % T4: periodic refresh every OPT_PERIOD_MIN minutes (restored default)
        if (k - last_opt_step) >= OPT_PERIOD_STEPS
            trig = true;
        end

        % ============ Layer 1: optimise ============
        if trig
            best_J = Inf;
            best_T_set = T_set;
            best_ac_on = ac_on;
            branch = 'none';

            if cur_occ
                % OCCUPIED: search S_cand for lowest cost candidate that is safe
                branch = 'occupied';
                cands = p.S_cand;
                for sp = cands
                    [E_pred, ~, ~, pen, safe] = layer1_physics( ...
                        T_in(k), T_out, N_occ, k, 30, true, sp, hem, p);
                    if ~safe, continue; end
                    % Bias toward EMA-learned preference (small term)
                    pref_pen = 0.05 * (sp - learn.T_pref)^2;
                    J = E_pred + W_COMFORT * pen + pref_pen;
                    if J < best_J
                        best_J = J; best_T_set = sp; best_ac_on = true;
                    end
                end
                if isinf(best_J)
                    % No safe candidate -> pick the coolest (safety override)
                    best_T_set = min(p.S_cand); best_ac_on = true;
                    branch = 'occupied_safety_override';
                end
            else
                % UNOCCUPIED
                if P_occ_future >= p.P_occ_thr
                    % Pre-cool: drive toward learned preference
                    best_T_set = max(p.T_min, min(p.T_max, learn.T_pref));
                    best_ac_on = true;
                    branch = 'precool';
                else
                    % Setback: try OFF; if it stays safe, OFF wins on energy.
                    [E_off,~,~,~, safe_off] = layer1_physics( ...
                        T_in(k), T_out, N_occ, k, 30, false, p.T_setback, hem, p);
                    if safe_off
                        best_T_set = p.T_setback; best_ac_on = false; best_J = E_off;
                        branch = 'setback_off';
                    else
                        % Hold at setback with AC on
                        best_T_set = p.T_setback; best_ac_on = true;
                        branch = 'setback_forced_on';
                    end
                end
            end

            T_set            = best_T_set;
            ac_on            = best_ac_on;
            last_opt_step    = k;
            load_at_last_opt = load_now;                   % T3 baseline reset
            last_branch      = branch;                      % diagnostic: which decision path fired
        end

        trigger_log(k) = trig;
        branch_log(k)  = string(last_branch);



        % ============ Step the physics ============
        [Q_cool, P_elec, hem, info] = hem_step(T_in(k), T_out(k), T_set, ac_on, hem, p);
        [T_in(k+1), ~]              = btm_step(T_in(k), T_out(k), N_occ(k), Q_cool, t_hour(k), p);

        T_set_log(k)  = T_set;
        P_elec_log(k) = P_elec;
        Q_cool_log(k) = Q_cool;
        is_on_log(k)  = hem.is_on;
        ac_on_log(k)  = ac_on;
        f_mod_log(k)  = info.f_mod;
        U_est_log(k)  = learn.U_est;
        Tpref_log(k)  = learn.T_pref;

        prev_occ = cur_occ;
    end

    % carry final-step logs forward
    T_set_log(p.N)  = T_set;
    P_elec_log(p.N) = P_elec;
    Q_cool_log(p.N) = Q_cool;
    is_on_log(p.N)  = hem.is_on;
    ac_on_log(p.N)  = ac_on;
    f_mod_log(p.N)  = info.f_mod;
    U_est_log(p.N)  = learn.U_est;
    Tpref_log(p.N)  = learn.T_pref;
    branch_log(p.N) = branch_log(p.N-1);

    % --- pack log ---
    log.name        = 'hybrid';
    log.T_in        = T_in;
    log.T_set       = T_set_log;
    log.P_elec      = P_elec_log;
    log.Q_cool      = Q_cool_log;
    log.is_on       = is_on_log;
    log.ac_on       = ac_on_log;
    log.f_mod       = f_mod_log;
    log.T_out       = T_out;
    log.N_occ       = N_occ;
    log.trigger     = trigger_log;
    log.branch      = branch_log;                  % diagnostic: 'precool'/'setback_off'/'setback_forced_on'/'occupied'/'occupied_safety_override'
    log.U_est       = U_est_log;
    log.T_pref      = Tpref_log;
    log.learn_final = learn;
end
