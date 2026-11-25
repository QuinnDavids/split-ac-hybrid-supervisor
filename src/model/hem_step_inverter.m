function [Q_cool, P_elec, state_new, info] = hem_step_inverter(T_in, T_out, T_set, ac_on, state, p)
%HEM_STEP_INVERTER  Advance the inverter HVAC Energy Model by one Euler step.
%   [Q_cool, P_elec, state_new, info] = HEM_STEP_INVERTER(T_in, T_out, T_set, ac_on, state, p)
%
%   Revision note: this is the renamed content of the original hem_step.m (pure
%   rename, NO logic changes). hem_step.m is now a thin dispatcher that
%   calls either this function or hem_step_bangbang.m based on
%   p.hvac_type. Called directly here only by sanity_hem.m and anywhere
%   that explicitly wants the inverter model regardless of p.hvac_type.
%
%   Inputs
%     T_in   : indoor air temperature                (degC)
%     T_out  : outdoor air temperature               (degC)
%     T_set  : commanded set-point from the controller (degC, ignored if ~ac_on)
%     ac_on  : logical -- is the AC UNIT powered? (false = breaker/remote OFF)
%              When false: Q_cool = 0, P_elec = 0, compressor forced off.
%     state  : struct carrying compressor state between steps
%                .is_on            (logical)
%                .t_since_change   (s, elapsed since last on/off transition)
%     p      : params struct (sim_params)
%
%   Outputs
%     Q_cool    : sensible heat extracted from the room this step (W >= 0)
%                 -> feeds btm_step as Q_cool.
%     P_elec    : electrical power drawn this step (W, real power)
%                 -> integrate to kWh.
%     state_new : updated state struct (pass into next call).
%     info      : struct of diagnostics (f_mod, COP, just_started).
%
%   Governing equations (Chapter 3):
%     f_mod = clip( (T_in - T_set)/dT_max , f_mod_min , 1 )         % Eq. 3.27
%     COP   = COP_nom - COP_degr * max(0, T_out - T_degr)           % Eq. 3.28
%     Q_cool   = f_mod * P_rated * COP                              % Eq. 3.26
%     P_elec   = f_mod * P_rated + P_fan                            % Eq. 3.31
%                + inrush term during the first inrush_s of a start % Eq. 3.32
%     E (kWh)  = sum( P_elec * dt ) / 3.6e6                         % Eq. 3.33
%   Min cycle: a switch is blocked if t_since_change < dt_min       % Eq. 3.14
%   ON/OFF deadband around T_set per p.deadband.

    % --- 0. Hard OFF: AC unit is unpowered ---
    if ~ac_on
        Q_cool = 0;
        P_elec = 0;
        state_new.is_on          = false;
        % t_since_change still ticks so min-cycle is satisfied by the time
        % the unit gets re-energised.
        if state.is_on
            state_new.t_since_change = 0;          % just switched off
        else
            state_new.t_since_change = state.t_since_change + p.dt;
        end
        info.f_mod = 0; info.COP = NaN; info.just_started = false;
        return;
    end

    % --- 1. Decide desired ON/OFF from deadband around T_set ---
    if T_in > T_set + p.deadband
        want_on = true;                 % too warm -> want cooling
    elseif T_in < T_set - p.deadband
        want_on = false;                % cool enough -> want off
    else
        want_on = state.is_on;          % inside deadband -> hold state
    end

    % --- 2. Apply minimum compressor cycle (Eq. 3.14) ---
    if want_on ~= state.is_on && state.t_since_change < p.dt_min
        want_on = state.is_on;          % switch blocked, hold previous state
    end

    just_started = want_on && ~state.is_on;
    is_on = want_on;

    % --- 3. Modulation fraction (Eq. 3.27) ---
    if is_on
        f_mod = (T_in - T_set) / p.dT_max;
        f_mod = max(p.f_mod_min, min(1.0, f_mod));
    else
        f_mod = 0;
    end

    % --- 4. COP with hot-condenser degradation (Eq. 3.28) ---
    COP = p.COP_nom - p.COP_degr * max(0, T_out - p.T_degr);

    % --- 5. Cooling capacity delivered to room (Eq. 3.26) ---
    Q_cool = f_mod * p.P_rated * COP;          % W (>=0)

    % --- 6. Electrical power draw (Eq. 3.31 + Eq. 3.32 inrush) ---
    P_comp = f_mod * p.P_rated;
    if is_on
        P_fan = p.P_fan;
    else
        P_fan = 0;
    end
    P_elec = P_comp + P_fan;

    % Inrush: extra power during the first inrush_s of any start (Eq. 3.32).
    % Modelled as step-averaged extra energy spread over this step:
    %   dE_inrush = (inrush_k - 1) * P_comp_nominal * inrush_s
    % giving an averaged power adder over the dt-second step.
    if just_started
        P_inrush_avg = (p.inrush_k - 1) * p.P_rated * (p.inrush_s / p.dt);
        P_elec = P_elec + P_inrush_avg;
    end

    % --- 7. Update state ---
    state_new.is_on = is_on;
    if is_on ~= state.is_on
        state_new.t_since_change = 0;          % switched this step
    else
        state_new.t_since_change = state.t_since_change + p.dt;
    end

    % --- 8. Diagnostics ---
    info.f_mod        = f_mod;
    info.COP          = COP;
    info.just_started = just_started;
end
