function [Q_cool, P_elec, state_new, info] = hem_step(T_in, T_out, T_set, ac_on, state, p)
%HEM_STEP  Dispatch to the configured HVAC Energy Model variant.
%   [Q_cool, P_elec, state_new, info] = HEM_STEP(T_in, T_out, T_set, ac_on, state, p)
%
%   Revision note: this file used to CONTAIN the inverter model directly. It is
%   now a thin dispatcher so that every strategy file (strategy_baseline,
%   strategy_scheduled, strategy_hybrid) and layer1_physics.m -- all of
%   which already call hem_step(...) generically -- can transparently run
%   either HVAC model with ZERO changes to their own code. Only the
%   caller's p.hvac_type field controls which physics model executes.
%
%   p.hvac_type = 'inverter' (or unset/missing) -> hem_step_inverter.m
%                  Modulating compressor, Eq. 3.26-3.27 f_mod curve.
%                  This is the ORIGINAL single-HVAC behaviour, and is
%                  the default so any existing script or params struct
%                  that predates p.hvac_type keeps running exactly as
%                  before -- nothing silently changes for old callers.
%
%   p.hvac_type = 'bangbang'                  -> hem_step_bangbang.m
%                  Fixed-speed compressor, binary ON/OFF (full rated
%                  capacity or nothing), no Eq. 3.27 modulation.
%
%   See hem_step_inverter.m / hem_step_bangbang.m for the full governing
%   equations and inputs/outputs -- the contract is identical between the
%   two, so this dispatcher adds no new documented behaviour of its own.

    if isfield(p, 'hvac_type') && strcmpi(p.hvac_type, 'bangbang')
        [Q_cool, P_elec, state_new, info] = hem_step_bangbang(T_in, T_out, T_set, ac_on, state, p);
    else
        % Default: 'inverter', or p.hvac_type missing entirely (backward
        % compatibility with any params struct/script written before
        % the bang-bang model was added, e.g. sim_params_okigwe.m, which never calls hem_step
        % anyway but is left untouched on principle).
        [Q_cool, P_elec, state_new, info] = hem_step_inverter(T_in, T_out, T_set, ac_on, state, p);
    end
end
