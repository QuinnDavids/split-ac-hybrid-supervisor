%GENERATE_HTML_REPORT  Bundle simulation results into ONE self-contained HTML file.
%
% Purpose
%   run_simulation.m (and run_sensitivity.m) produce PNGs (results/figures/)
%   and CSVs (results/tables/) as separate files. This script assembles the
%   KEY snapshots + metrics tables into a single static HTML file with
%   images embedded inline as base64 data URIs -- one portable file, whole
%   study in reading order, easy to share or archive as a single file.
%
%   NOT a replacement for explore_results.m (that stays the live,
%   interactive scrubbing tool). This is a STATIC EXPORT: full-study
%   traces, a zoomed eval-window snapshot per season (days learn_days+1 ..
%   learn_days+zoom_days, e.g. 15-17 under the current 14-day learn split),
%   metrics tables, cross-season contrast, and sensitivity results if
%   present.
%
% Auto-detecting dual structure support
%   This version auto-detects which results structure it's looking at:
%
%     LEGACY  (inverter-only runs): R.(season).(strategy).log/.m
%       -- the layout produced by earlier versions of run_simulation.m. Report renders
%       one HVAC-type's worth of sections, same as the original script.
%
%     MULTI-HVAC (current): R.(hvac_type).(season).(strategy)
%       -- hvac_type in {'inverter','bangbang'}. Report renders SEPARATE
%       figure sections per HVAC type (design choice: separate
%       figures per type, not one crowded 4-way chart), plus an added
%       "Inverter vs Bang-Bang" comparison section computed directly from
%       the in-memory R struct (not from CSVs, so it doesn't depend on
%       CSV file naming).
%
%   For legacy results this script behaves identically (in output) to
%   the original single-HVAC version. If run_simulation.m is ever changed
%   to nest the R struct differently than R.(hvac_type).(season).(strategy), the
%   detection logic below (Section 1) is the only place that needs editing.
%
% Requires
%   results/run_simulation_results.mat   (from run_simulation.m)
%   results/tables/metrics_<season>[_<hvac>].csv, metrics_combined.csv
%   results/figures/week_<season>[_<hvac>].png, bars_<season>[_<hvac>].png
%   Optional: results/tables/sensitivity_summary.csv,
%             results/figures/sensitivity_<season>.png
%             (sensitivity sweep is INVERTER-ONLY by scope
%             decision -- so no per-HVAC
%             suffix is expected here even in multi-HVAC mode)
%
% Output
%   results/report/simulation_report.html   <- upload THIS single file

clear; clc;

if ~exist('results/run_simulation_results.mat','file')
    error('generate_html_report:missing', ...
        'results/run_simulation_results.mat not found -- run run_simulation.m first.');
end
S = load('results/run_simulation_results.mat','R');
R = S.R;
p_ref = sim_params('hot');   % time-base + comfort-band fields, season-independent
strats  = {'baseline','scheduled','hybrid'};

if ~exist('results/report','dir'), mkdir('results/report'); end

% ---------------- 1. Detect results structure (legacy vs multi-HVAC) -------
KNOWN_SEASONS = {'hot','rain'};
KNOWN_HVAC    = {'inverter','bangbang'};

top_fields = fieldnames(R);
is_legacy     = all(ismember(top_fields, KNOWN_SEASONS));
is_multi_hvac = all(ismember(top_fields, KNOWN_HVAC));

if is_legacy
    % No HVAC-type dimension yet. Single implicit "type" with no filename
    % suffix, matching every file run_simulation.m writes today.
    hvac_types  = {''};
    seasons     = top_fields;
    getRun      = @(hvac, season, strat) R.(season).(strat);
elseif is_multi_hvac
    hvac_types  = top_fields;                       % {'inverter','bangbang'} (order as stored)
    seasons     = fieldnames(R.(hvac_types{1}));
    getRun      = @(hvac, season, strat) R.(hvac).(season).(strat);
else
    error('generate_html_report:structure', ...
        ['Unrecognized results struct: top-level fields are {%s}, which match ' ...
         'neither the legacy {hot,rain} layout nor the multi-HVAC {inverter,bangbang} ' ...
         'layout. If run_simulation.m nests R differently, update the ' ...
         'detection logic in Section 1 of this script.'], strjoin(top_fields, ','));
end

fprintf('generate_html_report: detected %s results structure (%d HVAC type(s), %d season(s)).\n', ...
    ternary(is_legacy, 'LEGACY single-HVAC', 'MULTI-HVAC'), numel(hvac_types), numel(seasons));

% ---------------- 2. Generate the zoomed eval-window snapshots -------------
% "What you'd scrub to by hand": a few days into the evaluation window, all
% three strategies overlaid, hybrid decision branch visible underneath.
steps_per_day  = 24*3600/p_ref.dt;
zoom_days      = 3;                                % show 3 eval days
zoom_start_day = p_ref.learn_days + 1;              % first eval day (day 15 @ learn_days=14)
zoom_idx_full  = (zoom_start_day-1)*steps_per_day + (1:zoom_days*steps_per_day);

zoom_png = struct();   % zoom_png.(hvac_key).(season) = png path
for hi = 1:numel(hvac_types)
    hvac = hvac_types{hi};
    hvac_key = hvac_field_key(hvac);   % '' -> 'none' (valid struct field)
    for s = 1:numel(seasons)
        season = seasons{s};
        run_b = getRun(hvac, season, 'baseline');
        run_s = getRun(hvac, season, 'scheduled');
        run_h = getRun(hvac, season, 'hybrid');

        zoom_idx_s = zoom_idx_full(zoom_idx_full <= p_ref.N);
        hh = (zoom_idx_s - 1) * p_ref.dt / 3600;

        fig = figure('Position',[60 60 1200 700], 'Visible','off');

        subplot(3,1,1);
        plot(hh, run_b.log.T_out(zoom_idx_s), 'k:', 'LineWidth', 1.0); hold on;
        plot(hh, run_b.log.T_in(zoom_idx_s),  'b-', 'LineWidth', 1.2);
        plot(hh, run_s.log.T_in(zoom_idx_s),  'r-', 'LineWidth', 1.2);
        plot(hh, run_h.log.T_in(zoom_idx_s),  'm-', 'LineWidth', 1.6);
        yline(p_ref.T_min,'g:'); yline(p_ref.T_max,'g:');
        xlabel('hours since window start'); ylabel('T (degC)'); grid on;
        legend({'T_{out}','Baseline','Scheduled','Hybrid','comfort band'}, 'Location','best');
        title(sprintf('%s season%s (Port Harcourt, Tier 2) -- eval days %d-%d -- indoor temperature', ...
            upper(season), hvac_title_suffix(hvac), zoom_start_day, zoom_start_day+zoom_days-1));

        subplot(3,1,2);
        plot(hh, run_b.log.P_elec(zoom_idx_s), 'b-'); hold on;
        plot(hh, run_s.log.P_elec(zoom_idx_s), 'r-');
        plot(hh, run_h.log.P_elec(zoom_idx_s), 'm-', 'LineWidth',1.3);
        xlabel('hours since window start'); ylabel('P_{elec} (W)'); grid on;
        legend({'Baseline','Scheduled','Hybrid'}, 'Location','best');
        title('Electrical power');

        subplot(3,1,3);
        branch = run_h.log.branch(zoom_idx_s);
        branch_names = unique(branch);
        branch_num = zeros(size(branch));
        for bi = 1:numel(branch_names)
            branch_num(branch == branch_names(bi)) = bi;
        end
        stairs(hh, branch_num, 'm-', 'LineWidth', 1.3);
        yticks(1:numel(branch_names)); yticklabels(cellstr(branch_names));
        xlabel('hours since window start'); ylabel('hybrid decision branch'); grid on;
        title('Hybrid controller decision branch over time');

        sgtitle(sprintf('%s%s -- zoomed eval-window snapshot (Port Harcourt, Tier 2)', ...
            upper(season), hvac_title_suffix(hvac)));

        png_path = sprintf('results/report/zoom_%s%s.png', season, hvac_file_suffix(hvac));
        exportgraphics(fig, png_path, 'Resolution', 150);
        close(fig);
        zoom_png.(hvac_key).(season) = png_path;
    end
end

% ---------------- 3. Assemble the HTML document -----------------------------
html = {};
html{end+1} = '<!DOCTYPE html><html><head><meta charset="UTF-8">';
html{end+1} = '<title>Hybrid HVAC Supervisory Framework -- Simulation Report</title>';
html{end+1} = ['<style>body{font-family:Arial,sans-serif;max-width:1100px;margin:30px auto;' ...
    'padding:0 20px;line-height:1.5;} h1{border-bottom:3px solid #333;} ' ...
    'h2{border-bottom:1px solid #999;margin-top:40px;} ' ...
    'h3{margin-top:25px;} ' ...
    'table{margin:10px 0;border-collapse:collapse;} ' ...
    'th,td{border:1px solid #ccc;} ' ...
    '.note{background:#f5f5f5;border-left:4px solid #888;padding:8px 12px;' ...
    'margin:10px 0;font-size:0.9em;} ' ...
    '.hvac-block{border:1px solid #ddd;border-radius:6px;padding:0 20px 10px;margin:20px 0;' ...
    'background:#fbfbfb;}</style></head><body>'];

html{end+1} = '<h1>Hybrid HVAC Supervisory Framework — Simulation Report</h1>';
html{end+1} = sprintf('<p class="note">Generated %s. Port Harcourt (Tier 2), calibrated parameters ', ...
    datestr(now));
html{end+1} = sprintf(['(C_th = %.0f J/K, U_comp = %.2f W/m^2K, solar_factor_rain = %.3f -- ' ...
    'calibrated against Ogbonnaya (2019) Okigwe field data, Tier 1). ' ...
    'Comfort band %.0f-%.0f&deg;C, setback %.0f&deg;C. Study: %d days ' ...
    '(%d-day learn / %d-day eval).</p>'], ...
    p_ref.C_th, p_ref.U_comp, sim_params('rain').solar_factor, ...
    p_ref.T_min, p_ref.T_max, p_ref.T_setback, ...
    p_ref.days, p_ref.learn_days, p_ref.days-p_ref.learn_days);

if is_multi_hvac
    html{end+1} = sprintf(['<p class="note"><b>Multi-HVAC results detected</b> -- this report covers ' ...
        '%d HVAC configurations (%s), each run through all %d strategies x %d seasons. ' ...
        'Each configuration gets its own figure set below (kept ' ...
        'visually separate rather than a single crowded comparison chart), followed by a direct ' ...
        'Inverter vs Bang-Bang comparison section.</p>'], ...
        numel(hvac_types), strjoin(hvac_types, ' / '), numel(strats), numel(seasons));
end

% ---- per-HVAC-type, per-season sections ----
for hi = 1:numel(hvac_types)
    hvac = hvac_types{hi};
    hvac_key = hvac_field_key(hvac);

    if is_multi_hvac
        html{end+1} = sprintf('<div class="hvac-block"><h2>%s compressor configuration</h2>', ...
            upper(hvac)); %#ok<AGROW>
    end

    for s = 1:numel(seasons)
        season = seasons{s};
        html{end+1} = sprintf('<h2>%s season%s</h2>', upper(season), hvac_title_suffix(hvac)); %#ok<AGROW>

        html{end+1} = sprintf('<h3>Full-study trace (all %d days)</h3>', p_ref.days); %#ok<AGROW>
        week_png = resolve_path({ ...
            sprintf('results/figures/week_%s%s.png', season, hvac_file_suffix(hvac)), ...
            sprintf('results/figures/week_%s.png', season) });
        html{end+1} = render_img_or_note(week_png, sprintf('%s%s full study trace', season, hvac_title_suffix(hvac))); %#ok<AGROW>

        html{end+1} = sprintf('<h3>Zoomed eval-window snapshot (days %d-%d)</h3>', ...
            zoom_start_day, zoom_start_day+zoom_days-1); %#ok<AGROW>
        html{end+1} = img_tag(zoom_png.(hvac_key).(season), ...
            sprintf('%s%s zoomed eval window', season, hvac_title_suffix(hvac))); %#ok<AGROW>

        html{end+1} = '<h3>Energy / ESI / TCSR comparison</h3>'; %#ok<AGROW>
        bars_png = resolve_path({ ...
            sprintf('results/figures/bars_%s%s.png', season, hvac_file_suffix(hvac)), ...
            sprintf('results/figures/bars_%s.png', season) });
        html{end+1} = render_img_or_note(bars_png, sprintf('%s%s bar comparison', season, hvac_title_suffix(hvac))); %#ok<AGROW>

        html{end+1} = '<h3>Metrics table (evaluation window)</h3>'; %#ok<AGROW>
        metrics_csv = resolve_path({ ...
            sprintf('results/tables/metrics_%s%s.csv', season, hvac_file_suffix(hvac)), ...
            sprintf('results/tables/metrics_%s.csv', season) });
        html{end+1} = csv_table(metrics_csv); %#ok<AGROW>
    end

    if is_multi_hvac
        html{end+1} = '</div>'; %#ok<AGROW>
    end
end

% ---- cross-season contrast (per HVAC type if multi) ----
html{end+1} = '<h2>Cross-season contrast</h2>';
combined_csv = resolve_path({'results/tables/metrics_combined.csv'});
html{end+1} = csv_table(combined_csv);

% ---- Inverter vs Bang-Bang comparison (multi-HVAC mode only) ----
if is_multi_hvac
    html{end+1} = '<h2>Inverter vs Bang-Bang comparison</h2>';
    html{end+1} = ['<p class="note">Computed directly from the in-memory results struct ' ...
        '(not from CSVs), so this section is independent of whatever file-naming ' ...
        'convention run_simulation.m uses for per-HVAC-type exports.</p>'];

    headers = {'HVAC_Type','Season','Strategy','E_kWh','ESI_pct','TCSR_pct','MTD_degC','FCS_NGN'};
    rows = cell(0, numel(headers));   % pre-shaped so (end+1,:) row-append works
    for hi = 1:numel(hvac_types)
        hvac = hvac_types{hi};
        for s = 1:numel(seasons)
            season = seasons{s};
            for st = 1:numel(strats)
                strat = strats{st};
                m = getRun(hvac, season, strat).m;
                rows(end+1,:) = { upper(hvac), upper(season), strat, ...
                    sprintf('%.2f', m.E_kWh), sprintf('%+.2f', m.ESI), ...
                    sprintf('%.2f', m.TCSR), sprintf('%.2f', m.MTD), ...
                    sprintf('%.0f', m.FCS_NGN) }; %#ok<AGROW>
            end
        end
    end
    html{end+1} = rows_to_html_table(headers, rows);

    % Headline verdict: which HVAC type wins on hybrid ESI, per season
    html{end+1} = '<h3>Headline: which configuration saves more energy?</h3>';
    verdict_lines = {'<ul>'};
    for s = 1:numel(seasons)
        season = seasons{s};
        best_hvac = ''; best_esi = -Inf;
        line_parts = {};
        for hi = 1:numel(hvac_types)
            hvac = hvac_types{hi};
            m = getRun(hvac, season, 'hybrid').m;
            line_parts{end+1} = sprintf('%s ESI = %+.2f%%', upper(hvac), m.ESI); %#ok<AGROW>
            if m.ESI > best_esi
                best_esi = m.ESI; best_hvac = hvac;
            end
        end
        verdict_lines{end+1} = sprintf('<li><b>%s season:</b> %s &rarr; <b>%s</b> performs better on hybrid ESI.</li>', ...
            upper(season), strjoin(line_parts, ' vs. '), upper(best_hvac)); %#ok<AGROW>
    end
    verdict_lines{end+1} = '</ul>';
    html{end+1} = strjoin(verdict_lines, '');
end

% ---- sensitivity sweep (inverter-only by scope decision) ----
if exist('results/tables/sensitivity_summary.csv','file')
    html{end+1} = '<h2>Sensitivity sweep (C_th, U_comp, COP_nom)</h2>';
    if is_multi_hvac
        html{end+1} = ['<p class="note">Sensitivity analysis was run on the INVERTER configuration ' ...
            'only (scope decision). Bang-bang robustness ' ...
            'under parameter uncertainty is not covered here.</p>'];
    end
    for s = 1:numel(seasons)
        season = seasons{s};
        sens_png = sprintf('results/figures/sensitivity_%s.png', season);
        if exist(sens_png,'file')
            html{end+1} = sprintf('<h3>%s season</h3>', upper(season)); %#ok<AGROW>
            html{end+1} = img_tag(sens_png, sprintf('%s sensitivity sweep', season)); %#ok<AGROW>
        end
    end
    html{end+1} = '<h3>Sensitivity summary table</h3>';
    html{end+1} = csv_table('results/tables/sensitivity_summary.csv');
else
    html{end+1} = '<p class="note">No sensitivity results found -- run run_sensitivity.m to include them.</p>';
end

html{end+1} = '</body></html>';

out_path = 'results/report/simulation_report.html';
fid = fopen(out_path, 'w');
fprintf(fid, '%s', strjoin(html, "\n"));
fclose(fid);

fprintf('\n>> Report written to %s\n', out_path);
fprintf('>> This is ONE self-contained file (images embedded as base64) --\n');
fprintf('   share or archive this single file.\n\n');

% ============================================================================
% ---------------- Helper functions -----------------------------------------
% ============================================================================

function key = hvac_field_key(hvac)
    % '' is not a valid MATLAB struct field name -- map legacy (no HVAC
    % dimension) to a placeholder key so zoom_png.(key).(season) works.
    if isempty(hvac)
        key = 'none';
    else
        key = hvac;
    end
end

function suf = hvac_file_suffix(hvac)
    % Filename suffix, e.g. '_inverter'. Empty in legacy (single-type) mode.
    if isempty(hvac)
        suf = '';
    else
        suf = ['_' hvac];
    end
end

function suf = hvac_title_suffix(hvac)
    % Human-readable title suffix, e.g. ' (INVERTER)'. Empty in legacy mode.
    if isempty(hvac)
        suf = '';
    else
        suf = sprintf(' (%s)', upper(hvac));
    end
end

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end

function path = resolve_path(candidates)
    % Return the first candidate path that exists on disk, else ''.
    path = '';
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            path = candidates{i};
            return;
        end
    end
end

function html = render_img_or_note(png_path, alt_text)
    if isempty(png_path)
        html = sprintf('<p class="note"><em>Figure not found for: %s</em></p>', alt_text);
    else
        html = img_tag(png_path, alt_text);
    end
end

function html = img_tag(png_path, alt_text)
    fid = fopen(png_path, 'rb');
    bytes = fread(fid, Inf, '*uint8');
    fclose(fid);
    b64 = matlab.net.base64encode(bytes);
    html = sprintf('<img src="data:image/png;base64,%s" alt="%s" style="max-width:100%%; margin:10px 0;">', ...
        b64, alt_text);
end

function html = csv_table(csv_path)
    if isempty(csv_path)
        html = '<p><em>File not found.</em></p>';
        return;
    end
    fid = fopen(csv_path, 'r');
    if fid < 0
        html = sprintf('<p><em>File not found: %s</em></p>', csv_path);
        return;
    end
    lines = {};
    tline = fgetl(fid);
    while ischar(tline)
        lines{end+1} = tline; %#ok<AGROW>
        tline = fgetl(fid);
    end
    fclose(fid);

    html = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; font-size:0.9em;">';
    for i = 1:numel(lines)
        cols = strsplit(lines{i}, ',');
        if i == 1
            tag = 'th'; rowstyle = ' style="background:#eee;"';
        else
            tag = 'td'; rowstyle = '';
        end
        html = [html sprintf('<tr%s>', rowstyle)]; %#ok<AGROW>
        for c = 1:numel(cols)
            html = [html sprintf('<%s>%s</%s>', tag, cols{c}, tag)]; %#ok<AGROW>
        end
        html = [html '</tr>']; %#ok<AGROW>
    end
    html = [html '</table>'];
end

function html = rows_to_html_table(headers, rows)
    % Build an HTML table directly from an in-memory cell array (no CSV
    % round-trip needed) -- used for the Inverter-vs-Bang-Bang comparison,
    % which is computed live from the R struct.
    html = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse; font-size:0.9em;">';
    html = [html '<tr style="background:#eee;">'];
    for c = 1:numel(headers)
        html = [html sprintf('<th>%s</th>', headers{c})]; %#ok<AGROW>
    end
    html = [html '</tr>'];
    for r = 1:size(rows,1)
        html = [html '<tr>']; %#ok<AGROW>
        for c = 1:size(rows,2)
            html = [html sprintf('<td>%s</td>', rows{r,c})]; %#ok<AGROW>
        end
        html = [html '</tr>']; %#ok<AGROW>
    end
    html = [html '</table>'];
end
