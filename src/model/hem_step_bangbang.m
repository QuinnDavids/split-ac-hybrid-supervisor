function [Q_cool, P_elec, state_new, info] = hem_step_bangbang(T_in, T_out, T_set, ac_on, state, p)
%HEM_STEP_BANGBANG  Advance the fixed-speed (bang-bang) HVAC Energy Model by one Euler step.
%   [Q_cool, P_elec, state_new, info] = HEM_STEP_BANGBANG(T_in, T_out, T_set, ac_on, state, p)
%
%   Added for the fixed-speed comparison. Drop-in interface match with hem_step_inverter.m --
%   same signature, same state/info struct shapes -- so it can be called
%   through the hem_step.m dispatcher with zero changes to any strategy
%   file or layer1_physics.m.
%
%   Differences from the inverter model (hem_step_inverter.m):
%     - NO MODULATION. The compressor is either fully ON (rated capacity)
%       or fully OFF. There is no Eq. 3.27 fractional f_mod curve --
%       f_mod here is a DIAGNOSTIC placeholder only: 1.0 when ON, 0 when
%       OFF (kept so downstream logging code that reads info.f_mod, e.g.
%       strategy_*.m's f_mod_log, does not need to branch on HVAC type).
%     - ON/OFF decision uses the SAME deadband hysteresis logic as
%       hem_step_inverter.m: T_in > T_set + p.deadband -> want ON;
%       T_in < T_set - p.deadband -> want OFF; else hold previous state.
%     - SAME minimum-cycle protection (p.dt_min, Eq. 3.14). Bang-bang
%       units need this MORE than inverter units, not less -- short-
%       cycling under a fixed-speed compressor is precisely the failure
%       mode this model exists to characterise.
%     - SAME inrush model (Eq. 3.32, p.inrush_k / p.inrush_s) -- more
%       consequential here since bang-bang cycles more often than a
%       modulating compressor, so the inrush penalty compounds more
%       visibly in the results.
%     - Q_cool = P_rated * COP when ON (full rated capacity), 0 when OFF.
%       No f_mod scaling of either Q_cool or P_elec.
%
%   Inputs / Outputs: identical contract to hem_step_inverter.m. See that
%   file's header for the full field-by-field description.

    % --- 0. Hard OFF: AC unit is unpowered ---
    if ~ac_on
        Q_cool = 0;
        P_elec = 0;
        state_new.is_on          = false;
        if state.is_on
            state_new.t_since_change = 0;          % just switched off
        else
            state_new.t_since_change = state.t_since_change + p.dt;
        end
        info.f_mod = 0; info.COP = NaN; info.just_started = false;
        return;
    end

    % --- 1. Decide desired ON/OFF from deadband around T_set (same as inverter) ---
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

    % --- 3. NO MODULATION: binary full-load / off (bang-bang, no Eq. 3.27) ---
    if is_on
        f_mod = 1.0;
    else
        f_mod = 0;
    end

    % --- 4. COP with hot-condenser degradation (Eq. 3.28) -- same as inverter ---
    COP = p.COP_nom - p.COP_degr * max(0, T_out - p.T_degr);

    % --- 5. Cooling capacity delivered to room (Eq. 3.26 form, no f_mod) ---
    Q_cool = f_mod * p.P_rated * COP;          % W (>=0); f_mod is 0 or 1 here

    % --- 6. Electrical power draw ---
    P_comp = f_mod * p.P_rated;                % 0 or full P_rated, no partial draw
    if is_on
        P_fan = p.P_fan;
    else
        P_fan = 0;
    end
    P_elec = P_comp + P_fan;

    % Inrush: extra power during the first inrush_s of any start (Eq. 3.32).
    % Same averaged-energy-over-the-step model as the inverter, and more
    % consequential here because bang-bang starts more often.
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
    info.f_mod        = f_mod;         % 1.0 or 0 -- diagnostic placeholder, no fractional modulation
    info.COP          = COP;
    info.just_started = just_started;
end
