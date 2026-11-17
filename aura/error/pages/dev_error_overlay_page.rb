require "json"
require_relative "generic_error_page"

module Aura
  module Error
    module Pages
      class DevErrorOverlayPage
        def self.render(diagnostic: nil, inner: nil, diagnostics: nil, index: 0, config: nil, version: "dev", env: "development")
          if diagnostics.nil?
            return GenericErrorPage.render(diagnostic: diagnostic, inner: inner.to_s) if inner
            diagnostics = [diagnostic].compact
          end

          diags = Array(diagnostics).compact
          idx = [[index.to_i, 0].max, [diags.length - 1, 0].max].min
          current = diags[idx]
          total = [diags.length, 1].max

          <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{esc(current&.title || "Aura Error")}</title>
            <style>#{css}</style>
          </head>
          <body>
            <div class="aura-overlay" data-index="#{idx}" data-total="#{total}">
              #{header_html(idx, total, version, env, diags)}
              <main class="aura-main">
                #{diags.each_with_index.map { |d, i| error_panel_html(d, i, i == idx, config) }.join}
              </main>
            </div>
            <script>#{js}</script>
          </body>
          </html>
          HTML
        end

        def self.header_html(idx, total, version, env, _diags)
          prev_disabled = idx <= 0 ? " disabled" : ""
          next_disabled = idx >= total - 1 ? " disabled" : ""
          label = total == 1 ? "1 error" : "#{total} errors"
          <<~HTML
          <header class="aura-header">
            <div class="aura-header-left">
              <div class="aura-brand">
                <span class="aura-brand-mark">Aura</span>
                <span class="aura-dot"></span>
                <span class="aura-env">#{esc(env)}</span>
              </div>
              <div class="aura-nav">
                <button class="aura-icon-btn" data-action="prev"#{prev_disabled} aria-label="Previous error">‹</button>
                <span class="aura-counter">#{idx + 1}/#{total}</span>
                <button class="aura-icon-btn" data-action="next"#{next_disabled} aria-label="Next error">›</button>
              </div>
            </div>
            <div class="aura-header-right">
              <span class="aura-meta">Aura #{esc(version)}</span>
              <span class="aura-meta aura-meta-muted">#{esc(label)}</span>
            </div>
          </header>
          HTML
        end

        def self.error_panel_html(d, i, active, config)
          return "" unless d
          show_stack = config.nil? || !config.respond_to?(:show_stacktrace?) || config.show_stacktrace?
          show_suggestions = config.nil? || !config.respond_to?(:show_suggestions?) || config.show_suggestions?
          badge = esc(d.respond_to?(:badge_label) ? d.badge_label : "Runtime Error")
          title = esc(d.title.to_s.empty? ? "Error" : d.title)
          message = esc(d.message.to_s)
          klass = d.respond_to?(:exception_class) ? d.exception_class.to_s : ""
          loc = display_location(d.file, d.line, d.respond_to?(:column) ? d.column : nil)
          context_parts = []
          context_parts << klass unless klass.empty?
          context_parts << loc unless loc == "Unknown source"
          context_line = context_parts.join(" · ")

          causes = d.respond_to?(:causes) ? Array(d.causes) : []
          causes_html = causes.empty? ? "" : causes.map { |c| cause_html(c, config) }.join

          code_html = show_stack ? code_frame_html(d.file, d.line, d.respond_to?(:column) ? d.column : nil) : ""
          stack_html = show_stack ? call_stack_html(Array(d.stack)) : ""
          suggestions = d.respond_to?(:suggestions) ? Array(d.suggestions) : []
          suggestions_html = (show_suggestions && !suggestions.empty?) ? suggestions_html_block(suggestions) : ""
          copy_payload = copy_text(d)

          <<~HTML
          <section class="aura-error-panel#{active ? " is-active" : ""}" data-panel="#{i}">
            <div class="aura-error-head">
              <div class="aura-badge">#{badge}</div>
              <h1 class="aura-error-message">#{message.empty? ? esc(title) : message}</h1>
              #{context_line.empty? ? "" : "<div class=\"aura-error-context\">#{esc(context_line)}</div>"}
              <div class="aura-actions">
                <button class="aura-btn" data-copy="error" data-copy-text="#{esc_attr(copy_payload[:error])}">Copy error</button>
                <button class="aura-btn" data-copy="stack" data-copy-text="#{esc_attr(copy_payload[:stack])}">Copy stack</button>
              </div>
            </div>
            #{code_html}
            #{stack_html}
            #{suggestions_html}
            #{causes_html}
          </section>
          HTML
        end

        def self.cause_html(d, config)
          show_stack = config.nil? || !config.respond_to?(:show_stacktrace?) || config.show_stacktrace?
          badge = esc(d.respond_to?(:badge_label) ? d.badge_label : "Runtime Error")
          klass = (d.respond_to?(:exception_class) && !d.exception_class.to_s.empty?) ? d.exception_class.to_s : "Error"
          msg = d.message.to_s
          <<~HTML
          <section class="aura-cause">
            <div class="aura-cause-label">Caused by</div>
            <div class="aura-cause-head">
              <span class="aura-badge aura-badge-sub">#{badge}</span>
              <span class="aura-cause-title">#{esc(klass)}</span>
            </div>
            <div class="aura-cause-message">#{esc(msg)}</div>
            #{show_stack ? code_frame_html(d.file, d.line, d.respond_to?(:column) ? d.column : nil) : ""}
            #{show_stack ? call_stack_html(Array(d.stack), compact: true) : ""}
          </section>
          HTML
        end

        def self.code_frame_html(file, line, column)
          return "" unless file && line
          src = safe_read(file)
          return missing_source_html(file, line, column) unless src

          lines = src.lines
          total = lines.length
          target = line.to_i
          start = [target - 5, 1].max
          finish = [target + 5, total].min
          loc = display_location(file, target, column)

          body = (start..finish).map do |i|
            raw = lines[i - 1].to_s.chomp("\n")
            hl = highlight_ruby(raw)
            if i == target
              marker = "&gt;"
              caret = column ? caret_line(column) : ""
              "<div class=\"aura-code-line is-target\"><span class=\"aura-ln\">#{i}</span><span class=\"aura-marker\">#{marker}</span><code>#{hl}</code></div>#{caret}"
            else
              "<div class=\"aura-code-line\"><span class=\"aura-ln\">#{i}</span><span class=\"aura-marker\"></span><code>#{hl}</code></div>"
            end
          end.join

          <<~HTML
          <section class="aura-block">
            <div class="aura-block-header">
              <span class="aura-block-title">Source</span>
              <span class="aura-block-meta" title="#{esc_attr(file.to_s)}">#{esc(loc)}</span>
            </div>
            <div class="aura-code">#{body}</div>
          </section>
          HTML
        end

        def self.caret_line(column)
          col = [column.to_i, 1].max
          pad = " " * (col - 1)
          "<div class=\"aura-code-caret\"><span class=\"aura-ln\"></span><span class=\"aura-marker\"></span><code>#{esc(pad)}^</code></div>"
        end

        def self.missing_source_html(file, line, column)
          loc = display_location(file, line, column)
          <<~HTML
          <section class="aura-block">
            <div class="aura-block-header">
              <span class="aura-block-title">Source</span>
              <span class="aura-block-meta">#{esc(loc)}</span>
            </div>
            <div class="aura-empty">Source file unavailable.</div>
          </section>
          HTML
        end

        def self.call_stack_html(stack, compact: false)
          frames = Array(stack).map { |l| parse_frame(l.to_s) }
          if frames.empty?
            return <<~HTML
            <section class="aura-block">
              <div class="aura-block-header"><span class="aura-block-title">Call Stack</span></div>
              <div class="aura-empty">No stack trace available.</div>
            </section>
            HTML
          end

          internal, app = frames.partition { |f| internal_frame?(f) }
          app_rows = app.map.with_index { |f, i| frame_row_html(f, i.zero? && !compact) }.join
          internal_rows = internal.map { |f| frame_row_html(f, false) }.join
          total = frames.length

          hidden_block = if internal.any?
            <<~HTML
            <div class="aura-internal is-hidden">#{internal_rows}</div>
            <button class="aura-link-btn" data-toggle-internal>Show #{internal.length} ignored frame#{internal.length == 1 ? "" : "s"}</button>
            HTML
          else
            ""
          end

          <<~HTML
          <section class="aura-block">
            <div class="aura-block-header">
              <span class="aura-block-title">Call Stack</span>
              <span class="aura-block-meta">#{total} frame#{total == 1 ? "" : "s"}</span>
            </div>
            <div class="aura-stack">#{app_rows}#{hidden_block}</div>
          </section>
          HTML
        end

        def self.frame_row_html(frame, open)
          file = frame[:file]
          line = frame[:line]
          method = frame[:method]
          loc = display_location(file, line, nil)
          label = method.to_s.strip
          label = loc if label.empty? || label == frame[:raw].to_s
          meta = (label == loc) ? "" : loc
          badge = internal_frame?(frame) ? '<span class="aura-frame-tag">internal</span>' : ""
          open_attr = open ? " open" : ""
          <<~HTML
          <details class="aura-frame"#{open_attr}>
            <summary>
              <span class="aura-frame-main">
                <span class="aura-frame-fn">#{esc(label.empty? ? "(unknown frame)" : label)}</span>
                #{meta.empty? ? "" : "<span class=\"aura-frame-loc\">#{esc(meta)}</span>"}
              </span>
              #{badge}
            </summary>
            <div class="aura-frame-body"><code>#{esc(frame[:raw].to_s)}</code></div>
          </details>
          HTML
        end

        def self.suggestions_html_block(suggestions)
          items = suggestions.map { |s| "<li>#{esc(s.to_s)}</li>" }.join
          <<~HTML
          <section class="aura-block">
            <div class="aura-block-header"><span class="aura-block-title">Possible fixes</span></div>
            <ul class="aura-suggestions">#{items}</ul>
          </section>
          HTML
        end

        def self.parse_frame(line)
          if defined?(Diagnostics::DiagnosticExtractor)
            Diagnostics::DiagnosticExtractor.parse_frame(line)
          else
            { file: nil, line: nil, method: line.to_s, raw: line.to_s }
          end
        rescue
          { file: nil, line: nil, method: line.to_s, raw: line.to_s }
        end

        def self.internal_frame?(frame)
          raw = frame[:raw].to_s
          file = frame[:file].to_s
          aura_root = File.expand_path(File.join(__dir__, "..", "..", ".."))
          return true if !aura_root.empty? && file.start_with?(aura_root)
          return true if file.include?("/aura/error/")
          return true if raw.include?("/lib/ruby/") || raw.include?("rubygems") || raw.include?("/gems/")
          return true if raw.include?("<internal:")
          false
        end

        def self.highlight_ruby(line)
          s = esc(line)
          placeholders = {}
          i = 0
          s = s.gsub(/(&quot;(?:[^&]|&(?!quot;))*?&quot;|&#39;(?:[^&]|&(?!#39;))*?&#39;)/) do
            k = "__AURA_STR_#{i}__"; i += 1; placeholders[k] = "<span class=\"tok-str\">#{$1}</span>"; k
          end
          s = s.gsub(/(#.*)$/) do
            k = "__AURA_COM_#{i}__"; i += 1; placeholders[k] = "<span class=\"tok-com\">#{$1}</span>"; k
          end
          s = s.gsub(/\b(def|end|class|module|if|elsif|else|unless|do|while|until|for|in|begin|rescue|ensure|raise|return|yield|super|self|nil|true|false|require|require_relative|include|extend|attr_reader|attr_writer|attr_accessor|case|when|then|and|or|not)\b/, '<span class="tok-kw">\1</span>')
          s = s.gsub(/\b([A-Z][A-Za-z0-9_]*)\b/, '<span class="tok-const">\1</span>')
          s = s.gsub(/\b(\d+(?:\.\d+)?)\b/, '<span class="tok-num">\1</span>')
          s = s.gsub(/(@{1,2}[A-Za-z_]\w*|:[A-Za-z_]\w*)/, '<span class="tok-sym">\1</span>')
          placeholders.each { |k, v| s = s.gsub(k, v) }
          s
        end

        def self.copy_text(d)
          err = +""
          klass = d.respond_to?(:exception_class) ? d.exception_class.to_s : ""
          err << "#{klass}: " unless klass.empty?
          err << (d.message || d.title || "Error").to_s
          err << "\n#{display_location(d.file, d.line, d.respond_to?(:column) ? d.column : nil)}" if d.file
          stack = Array(d.stack).join("\n")
          causes = d.respond_to?(:causes) ? Array(d.causes) : []
          causes.each do |c|
            cklass = (c.respond_to?(:exception_class) && c.exception_class) || "Error"
            err << "\n\nCaused by: #{cklass}: #{c.message}"
            stack << "\n\nCaused by: #{cklass}\n#{Array(c.stack).join("\n")}" unless Array(c.stack).empty?
          end
          { error: err, stack: stack }
        end

        def self.safe_read(path)
          return nil unless path && File.file?(path)
          File.read(path, encoding: "utf-8")
        rescue
          nil
        end

        def self.display_location(file, line, column)
          loc = relative_path(file).to_s
          return "Unknown source" if loc.empty?
          loc += ":#{line}" if line
          loc += ":#{column}" if column
          loc
        end

        def self.relative_path(path)
          return "" if path.nil?
          p = path.to_s
          root = File.expand_path(Dir.pwd)
          p.start_with?(root + File::SEPARATOR) ? p.delete_prefix(root + File::SEPARATOR) : p
        end

        def self.css
          <<~'CSS'
          :root{
            --bg:#000;--bg2:#080808;--bg3:#101010;--border:#252525;
            --text:#ededed;--muted:#a1a1aa;--faint:#6b6b73;
            --red:#f87171;--red-bg:rgba(248,113,113,.12);--green:#4ade80;
            --mono:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace;
            --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
          }
          *{box-sizing:border-box}
          html,body{margin:0;padding:0;background:var(--bg);color:var(--text);font-family:var(--sans);line-height:1.5}
          button{font:inherit;color:inherit}
          .aura-header{position:sticky;top:0;z-index:20;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 16px;border-bottom:1px solid var(--border);background:rgba(0,0,0,.92);backdrop-filter:saturate(120%) blur(4px)}
          .aura-header-left,.aura-header-right{display:flex;align-items:center;gap:14px;min-width:0}
          .aura-brand{display:flex;align-items:center;gap:8px;font-size:13px}
          .aura-brand-mark{font-weight:600;color:var(--text)}
          .aura-dot{width:6px;height:6px;border-radius:50%;background:var(--green);display:inline-block}
          .aura-env{color:var(--muted)}
          .aura-nav{display:flex;align-items:center;gap:6px}
          .aura-icon-btn{width:26px;height:26px;border:1px solid var(--border);background:var(--bg2);border-radius:6px;cursor:pointer;color:var(--muted);line-height:1}
          .aura-icon-btn:hover:not(:disabled){color:var(--text);border-color:#333}
          .aura-icon-btn:disabled{opacity:.35;cursor:default}
          .aura-counter,.aura-meta{font-size:12px;color:var(--muted);font-family:var(--mono)}
          .aura-meta-muted{color:var(--faint)}
          .aura-main{max-width:980px;margin:0 auto;padding:28px 20px 80px}
          .aura-error-panel{display:none}.aura-error-panel.is-active{display:block}
          .aura-error-head{margin-bottom:22px}
          .aura-badge{display:inline-flex;align-items:center;font-size:12px;font-weight:500;color:var(--red);margin-bottom:10px}
          .aura-badge-sub{margin:0 8px 0 0}
          .aura-error-message{margin:0;font-size:24px;line-height:1.35;font-weight:600;letter-spacing:-.02em;white-space:pre-wrap;word-break:break-word}
          .aura-error-context{margin-top:10px;font-size:13px;color:var(--muted);font-family:var(--mono);word-break:break-all}
          .aura-actions{display:flex;gap:8px;margin-top:14px;flex-wrap:wrap}
          .aura-btn{border:1px solid var(--border);background:var(--bg2);color:var(--text);font-size:12px;padding:6px 10px;border-radius:6px;cursor:pointer}
          .aura-btn:hover{border-color:#333;background:var(--bg3)}
          .aura-block{border:1px solid var(--border);border-radius:8px;overflow:hidden;background:var(--bg2);margin-top:16px}
          .aura-block-header{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 12px;border-bottom:1px solid var(--border);background:#0c0c0c}
          .aura-block-title{font-size:13px;font-weight:500;color:var(--text)}
          .aura-block-meta{font-size:12px;color:var(--muted);font-family:var(--mono);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .aura-code{overflow:auto;background:#000;font-family:var(--mono);font-size:13px;line-height:1.7}
          .aura-code-line,.aura-code-caret{display:grid;grid-template-columns:44px 18px 1fr;gap:0;min-width:100%;padding:0 12px 0 0}
          .aura-code-line{color:#a1a1aa}.aura-code-line.is-target{background:var(--red-bg);color:var(--text)}
          .aura-ln{color:#52525b;text-align:right;padding-right:10px;user-select:none}
          .aura-code-line.is-target .aura-ln{color:var(--red)}
          .aura-marker{color:var(--red);text-align:center;user-select:none}
          .aura-code-line code,.aura-code-caret code{white-space:pre}
          .aura-code-caret{color:var(--red)}
          .aura-stack{padding:4px}
          .aura-frame{border-radius:6px;margin:2px 0}
          .aura-frame summary{list-style:none;cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 10px}
          .aura-frame summary::-webkit-details-marker{display:none}
          .aura-frame:hover,.aura-frame[open]{background:var(--bg3)}
          .aura-frame-main{display:flex;flex-direction:column;gap:2px;min-width:0}
          .aura-frame-fn{font-size:13px;color:var(--text);font-family:var(--mono);word-break:break-all}
          .aura-frame-loc{font-size:12px;color:var(--muted);font-family:var(--mono);word-break:break-all}
          .aura-frame-tag{font-size:11px;color:var(--faint);border:1px solid var(--border);border-radius:999px;padding:1px 8px;white-space:nowrap}
          .aura-frame-body{padding:0 10px 10px 10px}
          .aura-frame-body code{font-family:var(--mono);font-size:12px;color:var(--muted);white-space:pre-wrap;word-break:break-all}
          .aura-internal.is-hidden{display:none}
          .aura-link-btn{margin:6px 8px 8px;background:none;border:none;color:var(--muted);font-size:12px;cursor:pointer;padding:4px 2px}
          .aura-link-btn:hover{color:var(--text)}
          .aura-empty{padding:14px 12px;color:var(--muted);font-size:13px}
          .aura-suggestions{margin:0;padding:12px 18px 12px 32px;color:#d4d4d8;font-size:13px}
          .aura-suggestions li{margin:6px 0}
          .aura-cause{margin-top:22px;padding-top:18px;border-top:1px solid var(--border)}
          .aura-cause-label{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px}
          .aura-cause-head{display:flex;align-items:center;gap:8px;margin-bottom:6px}
          .aura-cause-title{font-size:13px;color:var(--text);font-family:var(--mono)}
          .aura-cause-message{font-size:18px;font-weight:600;margin-bottom:4px;white-space:pre-wrap;word-break:break-word}
          .tok-kw{color:#c084fc}.tok-str{color:#86efac}.tok-com{color:#52525b}.tok-num{color:#fca5a5}.tok-const{color:#93c5fd}.tok-sym{color:#67e8f9}
          @media (max-width:720px){.aura-header{align-items:flex-start;flex-direction:column}.aura-main{padding:20px 14px 60px}.aura-error-message{font-size:20px}}
          CSS
        end

        def self.js
          <<~'JS'
          (function(){
            var root=document.querySelector('.aura-overlay');
            if(!root) return;
            var panels=[].slice.call(document.querySelectorAll('.aura-error-panel'));
            var idx=parseInt(root.getAttribute('data-index')||'0',10);
            var total=panels.length||1;
            function show(i){
              idx=Math.max(0,Math.min(total-1,i));
              panels.forEach(function(p,j){p.classList.toggle('is-active',j===idx);});
              var c=root.querySelector('.aura-counter'); if(c) c.textContent=(idx+1)+'/'+total;
              var prev=root.querySelector('[data-action="prev"]'); if(prev) prev.disabled=idx<=0;
              var next=root.querySelector('[data-action="next"]'); if(next) next.disabled=idx>=total-1;
              root.setAttribute('data-index', idx);
            }
            root.addEventListener('click', function(e){
              var t=e.target;
              var nav=t.closest('[data-action]');
              if(nav){
                if(nav.getAttribute('data-action')==='prev') show(idx-1);
                if(nav.getAttribute('data-action')==='next') show(idx+1);
                return;
              }
              var toggle=t.closest('[data-toggle-internal]');
              if(toggle){
                var block=toggle.previousElementSibling;
                if(block){ block.classList.toggle('is-hidden'); }
                var hidden=block && block.classList.contains('is-hidden');
                var m=toggle.textContent.match(/(\d+)/); var n=m?m[1]:'';
                toggle.textContent=hidden ? ('Show '+n+' ignored frame'+(n==='1'?'':'s')) : ('Hide '+n+' ignored frame'+(n==='1'?'':'s'));
                return;
              }
              var copy=t.closest('[data-copy]');
              if(copy){
                var text=copy.getAttribute('data-copy-text')||'';
                if(navigator.clipboard && navigator.clipboard.writeText){
                  navigator.clipboard.writeText(text).then(function(){
                    var old=copy.textContent; copy.textContent='Copied'; setTimeout(function(){copy.textContent=old;},1200);
                  }).catch(function(){ fallbackCopy(text, copy); });
                } else { fallbackCopy(text, copy); }
              }
            });
            function fallbackCopy(text, btn){
              var ta=document.createElement('textarea'); ta.value=text; document.body.appendChild(ta); ta.select();
              try{ document.execCommand('copy'); var old=btn.textContent; btn.textContent='Copied'; setTimeout(function(){btn.textContent=old;},1200);}catch(e){}
              document.body.removeChild(ta);
            }
            document.addEventListener('keydown', function(e){
              if(e.key==='ArrowLeft') show(idx-1);
              if(e.key==='ArrowRight') show(idx+1);
            });
            show(idx);
          })();
          JS
        end

        def self.esc(str)
          str.to_s.gsub("&","&amp;").gsub("<","&lt;").gsub(">","&gt;").gsub('"',"&quot;").gsub("'","&#39;")
        end

        def self.esc_attr(str)
          esc(str).gsub("\n","&#10;")
        end
      end
    end
  end
end

