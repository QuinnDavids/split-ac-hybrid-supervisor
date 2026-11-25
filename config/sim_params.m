function p = sim_params(season)
%SIM_PARAMS  Consolidated simulation parameters — Hybrid HVAC Supervisory Framework.
%   p = SIM_PARAMS(season) returns a struct of every constant used by the
%   Port Harcourt decentralized split-unit simulation (Chapter 3).
%
%   NOTE on the name: MATLAB Online ships a shadow file called params.m in
%   one of its support packages, so we use sim_params.m here to guarantee
%   our file is the one that gets called.
%
%   season : 'hot'  -> hot-dry / Harmattan scenario (default)
%            'rain' -> rainy-season scenario
%
%   Source tags in comments:
%     T3.3  = Table 3.3 (Consolidated Simulation Input Parameters)
%     O2019 = Ogbonnaya (2019) PhD thesis (same climate/building stock)
%     Eq.X  = governing equation number in Chapter 3
%   Values marked  [assumed]  are engineering assumptions where the report
%   leaves the value open or under-specified.

    if nargin < 1, season = 'hot'; end

    % ---------------- Simulation time base ----------------
    p.dt   = 60;                       % s     Euler time step            Eq.3.24, T3.3
    p.days = 28;                        % -     total duration             T3.3
    p.N    = p.days*24*3600/p.dt;      % = 40320 steps (28 days @ 60 s)

    % Strategy-3 learning vs evaluation split (avoid testing on training data)
    % Study length: 28 days. Days 1-14 = physics-only warm-up (Layer-2 learns).
    % Days 15-28   = evaluation window (all metrics computed here, all 3 strategies).
    % p.days and p.learn_days are read dynamically everywhere downstream
    % (metrics.m, run_simulation.m, run_sensitivity.m, strategy_hybrid.m), so
    % changing either number here is sufficient to rescale the whole study
    % (e.g. a future 1-year run would just need p.days/p.learn_days updated).
    p.learn_days = 14;                  % days 1-14: physics-only warm-up   [assumed]
    p.eval_days  = p.learn_days + 1;    % days 15-28: metrics computed here [assumed]

    % ---------------- Room geometry (drives A_env, A_roof, C_th) --------
    p.floor_area = 20;                 % m^2   typical room (15-25)       O2019  [assumed]
    p.height     = 2.7;                % m     ceiling height             O2019
    p.V_room     = p.floor_area*p.height;          % m^3
    side         = sqrt(p.floor_area);             % m (assume square room)
    p.A_wall     = 4*side*p.height;                % m^2  (no window subtraction) [assumed]
    p.A_roof     = p.floor_area;                   % m^2  flat-roof plan area
    p.A_env      = p.A_wall + p.A_roof;            % m^2  total exposed area

    % ---------------- Building Thermal Model (BTM) ---------------------
    p.U_comp  = 2.50;                  % W/m^2K  composite U-value        T3.3, Table 3.1
    p.rho_air = 1.18;                  % kg/m^3  air density at 30C       Eq.3.17
    p.cp_air  = 1005;                  % J/kgK   specific heat of air     Eq.3.17
    p.m_furn  = 150;                   % kg      furnishing mass/room     Eq.3.17
    p.cp_furn = 900;                   % J/kgK   specific heat furnishing Eq.3.17

    % C_th from Eq.3.17. Note: with the inputs above this yields
    % ~150,000-215,000 J/K, higher than the 20,000-50,000 J/K range in Table 3.3.
    % Sensitivity to C_th is tested in analysis/run_sensitivity.m (+/-50%);
    % the Okigwe validation uses a separately calibrated value (sim_params_okigwe.m).
    p.C_th = p.rho_air*p.V_room*p.cp_air + p.m_furn*p.cp_furn;  % J/K  [assumed; see note above]

    p.dT_sol = 5;                      % C       solar increment 10-16h   T3.3, Eq.3.21
    p.f_lat  = 0.40;                   % -       latent fraction (rainy)  T3.3, Eq.3.19

    % ---------------- Internal gains -----------------------------------
    p.q_met     = 100;                 % W/person  metabolic (sedentary)  T3.3
    p.P_equip   = 300;                 % W       equipment (range 200-400) T3.3  [assumed]
    p.N_occ_max = 2;                   % persons when occupied            [assumed]

    % ---------------- HVAC Energy Model (HEM) ---------------------------
    % hvac_type selects which physics model hem_step.m dispatches
    % to. Default 'inverter' preserves the original single-HVAC behaviour exactly --
    % nothing changes for any script that doesn't explicitly set this.
    p.hvac_type = 'inverter';          % 'inverter' | 'bangbang'
    p.P_rated   = 1100;                % W       1.5 HP rated power        T3.3
    p.P_fan     = 150;                 % W       indoor+outdoor fans       T3.3
    p.COP_nom   = 3.0;                 % -       nominal COP (2.8-3.2)     T3.3
    p.COP_degr  = 0.02;                % /C      COP loss per C >35C       Eq.3.28
    p.T_degr    = 35;                  % C       COP degradation onset     Eq.3.28
    p.PF        = 0.87;                % -       power factor              T3.3
    p.dT_max    = 4;                   % C       full-modulation diff.     Eq.3.27
    p.f_mod_min = 0.30;                % -       min inverter modulation   Eq.3.27
    p.inrush_k  = 1.8;                 % -       start-up inrush mult.     Eq.3.32
    p.inrush_s  = 5;                   % s       inrush duration           Eq.3.32

    % ---------------- Comfort & control bounds -------------------------
    p.T_min     = 23;                  % C       lower comfort (occupied)  T3.3, Ogbonnaya(2019) 23-27C band, revised (was 24)
    p.T_max     = 27;                  % C       upper comfort (occupied)  T3.3, Ogbonnaya(2019),            revised (was 26)
    p.T_setback = 30;                  % C       unoccupied setback        Eq.3.13, [assumed],               revised (was 28)
    p.S_cand    = [23 24 25 26 27];    % C       candidate set-points      Eq.3.15, matches new comfort band, revised (was [24 25 26 27 28])
    p.deadband  = 0.5;                 % C       ON/OFF hysteresis         [assumed; not specified in report]
    p.dt_min    = 300;                 % s       min compressor cycle      Eq.3.14

    % ---------------- Layer-2 adaptive learning ------------------------
    p.K_RLS       = 0.01;              % W/m^2K per C  RLS gain            Eq.3.8
    p.alpha       = 0.20;              % -       preference EMA rate        Eq.3.6
    p.P_occ_thr   = 0.70;              % -       pre-cool prob. threshold   Eq.3.9/3.10
    p.precool_min = 20;                % min     pre-cool lead time         §3.5.3
    p.err_thr     = 2.0;               % C       RLS trigger error          §3.5.3
    p.err_persist = 30;                % min     sustained-error window     §3.5.3

    % ---------------- Weather model (Eq.3.34) --------------------------
    % DIURNAL SWING: Port Harcourt is coastal humid-tropical, so the REAL swing
    % is modest (~6-12 C; Feb day ~34 / night ~25, met-station mean 31.3/21.8).
    % The chapter PROSE claim of a "20-26 C swing" is a desert/northern-Nigeria
    % figure and is physically wrong for PH -- do NOT inflate T_amp to match it.
    switch lower(season)
        case 'hot'    % hot-dry / Harmattan (Nov-Apr): hottest, sunniest, driest
            p.T_avg        = 32;       % C  daily mean (afternoon peak ~38)  T3.3  [assumed; cf. O2019]
            p.T_amp        = 6;        % C  diurnal amplitude (~12 C swing)  T3.3
            p.solar_factor = 1.00;     % -  full solar gain (clear skies)    [assumed]
            p.use_latent   = false;    %    negligible dehumidification load
        case 'rain'   % rainy / monsoon (May-Oct): cloudy, humid, cooler
            p.T_avg        = 26;       % C  daily mean                       T3.3
            p.T_amp        = 4;        % C  smaller swing under cloud cover   [assumed; cf. O2019]
            p.solar_factor = 0.50;     % -  reduced solar (~3-5 vs ~8 sun-h)  [assumed]
            p.use_latent   = true;     %    latent load applies (Eq.3.19)
        otherwise
            error('params:season','season must be ''hot'' or ''rain''.');
    end
    p.season = lower(season);
    p.t_peak = 15;                     % h   daily peak time                  T3.3
    % Apply in BTM:  Q_sol = solar_factor * U_comp * A_roof * dT_sol  (10-16h)
    % Apply latent:  if use_latent, Q_env_eff = Q_env * (1 + f_lat)   (Eq.3.19)

    % ---------------- Occupancy generation (§3.6.4) --------------------
    p.hours_weekday = 12;              % h/day  AC usage weekday           §3.6.4
    p.hours_weekend = 16;              % h/day  AC usage weekend           §3.6.4

    % ---------------- Strategy 1 (Baseline / manual) -------------------
    p.base_T_initial    = 18;          % C    arrival set-point            §3.6.3
    p.base_T_comfort    = 22;          % C    raised set-point             §3.6.3
    p.base_raise_min    = 30;          % min  dwell before raise to 22C    [assumed]
    p.base_leaveon_prob = 0.50;        % -    prob. of leaving AC on       §3.6.3

    % ---------------- Strategy 2 (Scheduled) ---------------------------
    p.sched_setpoint = 22;             % C    scheduled occupied set-point §3.6.3
    % Fixed schedule (occupied = true):
    %   weekday: 06:00-08:00 and 18:00-23:00 ; weekend: 07:00-23:00
    % Realized occupancy (occupancy_profile.m) WILL diverge from this.

    % ---------------- Economics (Eq.3.38) ------------------------------
    p.eta_gen   = 0.30;                % kWh_e/kWh_fuel  generator eff.    Eq.3.38
    p.CV_diesel = 9.9;                 % kWh/litre   diesel calorific val. Eq.3.38
    p.C_diesel  = 1650;                % NGN/litre   diesel unit cost      Eq.3.38, Aug-2026 PH-region estimate, revised (was 1350) -- volatile, treat as estimate
    p.C_grid    = 250;                 % NGN/kWh     grid tariff (Band A)  Eq.3.39, used by analysis/grid_cost_saving.m only

    % ---------------- Reproducibility ----------------------------------
    p.seed = 2025;                     % fixed RNG seed: SAME profiles for all strategies
end
