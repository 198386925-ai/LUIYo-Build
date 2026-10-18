import Foundation

/// JavaScript injected into the bundled page. The HTML owns the design; these
/// scripts only add the activation entry and seed one localStorage default.
enum BridgeScripts {
    /// Seed the bottom-search mode before the page reads it (fresh installs only).
    static let bottomSearchBootstrap = """
    if(localStorage.getItem('youyou.theme.bottomSearchMode')===null && localStorage.getItem('youyou.theme.bottomSearchEnabled')===null){localStorage.setItem('youyou.theme.bottomSearchMode','separate')}
    """

    /// Inline activation card + authorization gate injected into the settings page.
    /// Unchanged from the shipped build: the HTML design and the
    /// `window.__luiyoSetAuthorized` hook are part of the app contract.
    static let activationPreviewScript = #"""
    (() => {
      let authorized = false;
      const css = document.createElement('style');
      css.textContent = `.luiyoActivationEntry{margin:0 0 8px;padding:17px 18px;border:0;border-radius:28px;background:var(--card-color,#fff)}
        body.native-card-glass .luiyoActivationEntry{background:transparent!important;box-shadow:none!important}
        .luiyoActivationEntry strong{display:block;font-size:15px}.luiyoActivationEntry small{display:block;margin-top:5px;color:var(--muted,#8b8f98);font-size:12px}
        .luiyoActivationForm{display:flex;gap:8px;margin:8px 12px 12px!important;align-items:center}.luiyoActivationForm[hidden]{display:none!important}
        #luiyoLicenseCode{flex:1;min-width:0;height:44px;box-sizing:border-box;padding:0 12px;border:0;border-radius:22px;background:transparent;color:inherit;font-size:14px}
        #luiyoLicenseSubmit{height:44px;border:0;border-radius:22px;padding:0 14px;background:#6968e8;color:white;font-weight:600;white-space:nowrap}
        body.native-card-glass #luiyoLicenseSubmit{background:transparent!important;color:transparent!important}
        body.native-card-glass #luiyoLicenseCode{background:transparent!important;border:0!important}`;
      document.head.appendChild(css);
      const settings = document.getElementById('settingsTarget');
      if (settings) {
        const box = document.createElement('section');
        box.className = 'luiyoActivationEntry';box.id='luiyoActivationCard';
        box.innerHTML = '<div class="settingsAuthHeading"><span class="settingsFoldIcon" data-system-icon="checkmark.shield">✓</span><span class="settingsFoldText"><b>激活授权</b><small id="luiyoAuthState">未激活 · 仅可浏览</small></span></div><form class="luiyoActivationForm" id="luiyoActivationForm"><input id="luiyoLicenseCode" aria-label="卡密" placeholder="输入卡密" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false"><button id="luiyoLicenseSubmit" type="submit">激活</button></form>';
        settings.querySelector('.settingsHead')?.insertAdjacentElement('afterend', box);
        const hero=document.createElement('div');hero.id='luiyoSettingsHero';hero.style.cssText='height:116px;margin-bottom:8px';
        box.insertAdjacentElement('beforebegin',hero);
        let queued=false,last='';
        const syncHero=()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;const r=hero.getBoundingClientRect();const payload={visible:!!hero.getClientRects().length,x:r.left+scrollX,y:r.top+scrollY,width:r.width,height:r.height};const signature=JSON.stringify(payload);if(signature!==last){last=signature;window.webkit?.messageHandlers?.settingsHeroFrame?.postMessage(payload)}})};
        if(window.ResizeObserver)new ResizeObserver(syncHero).observe(settings);
        new MutationObserver(syncHero).observe(document.body,{subtree:true,attributes:true,childList:true,characterData:true});
        window.addEventListener('resize',syncHero);syncHero();
        box.querySelector('form').addEventListener('submit', e => {
          e.preventDefault();const code=box.querySelector('input').value.trim();
          if(code)window.webkit?.messageHandlers?.activationSubmit?.postMessage({code});
        });
      }
      window.__luiyoSetAuthorized = (enabled,message,busy=false) => {
        authorized = !!enabled;
        document.documentElement.dataset.luiyoAuthorized = authorized ? 'yes' : 'no';
        const state=document.getElementById('luiyoAuthState'), form=document.getElementById('luiyoActivationForm');
        if(state)state.textContent=message||(authorized?'已授权':'未激活 · 仅可浏览');
        if(form){form.hidden=authorized;const field=form.querySelector('input'),button=form.querySelector('button');field.disabled=busy;button.disabled=busy;button.textContent=busy?'验证中…':'激活';if(authorized){field.blur();field.value=''}}
        window.__syncNativeCardGlass?.();
      };
      function showLicenseNotice() {
        let el=document.getElementById('luiyoLicenseNotice');
        if(!el) {
          el=document.createElement('div');
          el.id='luiyoLicenseNotice';
          el.setAttribute('role','status');
          el.style.cssText='position:fixed;z-index:2147483647;left:50%;bottom:calc(env(safe-area-inset-bottom,0px) + 94px);transform:translateX(-50%);max-width:calc(100vw - 36px);box-sizing:border-box;padding:13px 20px;border-radius:16px;color:#fff;background:rgba(35,36,44,.92);font-size:14px;font-weight:600;text-align:center;box-shadow:0 5px 24px rgba(0,0,0,.18);pointer-events:none';
          document.body.appendChild(el);
        }
        el.textContent='未授权用户，请授权后使用';
        el.hidden=false;
        clearTimeout(window.__luiyoNoticeTimeout);
        window.__luiyoNoticeTimeout=setTimeout(()=>{el.hidden=true},2300);
      }
      function protect(e) {
        if(authorized) return;
        const t=e.target;
        if(!(t instanceof Element) || !t.closest('#homeTools'))return;
        if(!t.closest('button,input,textarea,select,label,a,[contenteditable],[role="button"]'))return;
        e.preventDefault();e.stopImmediatePropagation();
        if(e.type==='click')showLicenseNotice();
      }
      ['click','change','input','submit','keydown','drop','paste'].forEach(t=>document.addEventListener(t,protect,true));
      window.__luiyoSetAuthorized(false);
    })();
    """#

    /// Loads a script bundled inside Web/.
    static func bundled(named name: String, extension fileExtension: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Web"),
              let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return script
    }
}
