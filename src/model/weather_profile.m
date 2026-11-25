function T_out = weather_profile(p)
%WEATHER_PROFILE  Outdoor dry-bulb temperature trace for the full simulation.
%   T_out = WEATHER_PROFILE(p) returns a column vector of length p.N giving
%   the outdoor temperature (degC) at every Euler step dt.
%
%   Model:  T_out(t) = T_avg + T_amp * cos(2*pi*(t_hour - t_peak)/24)   % Eq. 3.34
%
%   Per-season values come from params.m:
%     hot  : T_avg=32, T_amp=6   (Harmattan/dry, peak ~38C)
%     rain : T_avg=26, T_amp=4   (cloudy/wet, peak ~30C)
%   t_peak = 15 h (mid-afternoon).
%
%   Deterministic given p.seed -- no stochastic component.

    t_s     = (0:p.N-1).' * p.dt;            % s, simulation time vector
    t_hour  = mod(t_s/3600, 24);             % h, hour of day (0-24)

    T_out = p.T_avg + p.T_amp * cos(2*pi*(t_hour - p.t_peak)/24);   % Eq. 3.34
end
