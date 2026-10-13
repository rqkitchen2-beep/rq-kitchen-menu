/* RQ i18n: the pages are written in Arabic; in English mode every Arabic phrase on
   screen is swapped for its English text (exact phrase first, then the longest known
   phrases word by word), the page turns left-to-right, and new content is translated
   as it appears. Language = saved choice, else Arabic. */
(function(){
  var KEY='rq-lang', lang='ar';
  try{lang=localStorage.getItem(KEY)||'';}catch(e){}
  if(lang!=='ar'&&lang!=='en')lang='ar';
  window.RQLANG=lang;
  var D=__DICT__;
  var RUN=/[؀-ۿ][؀-ۿً-ْ ،؟؛]*[؀-ۿ؟]|[؀-ۿ]/g;
  var NA='(?![\\u0600-\\u06FF])';
  var PATS=[
    [/(\d{1,2}:\d{2})\s?ص/g,'$1 AM'],[/(\d{1,2}:\d{2})\s?م/g,'$1 PM'],
    [/دقة (\d+) م/g,'accuracy $1 m'],
    [new RegExp('قبل (\\d+) د'+NA,'g'),'$1 min ago'],[new RegExp('قبل (\\d+) س'+NA,'g'),'$1 h ago'],
    [new RegExp('(\\d+) د'+NA,'g'),'$1 min'],[new RegExp('(\\d+) س'+NA,'g'),'$1 h'],
    [/([\d.]+) كم/g,'$1 km'],[/مختارات RQ/g,'RQ Picks'],[/(\d+)×/g,'$1×']
  ];
  var MAXW=1;for(var k in D){var w=k.split(' ').length;if(w>MAXW)MAXW=w;}
  function trRun(r){
    if(D[r]!=null)return D[r];
    var ws=r.split(/\s+/),out=[],i=0;
    while(i<ws.length){var hit=null,n;
      for(n=Math.min(MAXW,ws.length-i);n>0;n--){var p=ws.slice(i,i+n).join(' ');if(D[p]!=null){hit=D[p];break;}
        var q=p.replace(/[،؟؛]+$/,'');if(q!==p&&D[q]!=null){hit=D[q]+(p.slice(q.length)==='؟'?'?':',');break;}}
      if(hit!=null){out.push(hit);i+=n;}else{out.push(ws[i]);i++;}}
    return out.join(' ');
  }
  function tr(s){
    if(!s||!/[؀-ۿ]/.test(s))return s;
    for(var i=0;i<PATS.length;i++)s=s.replace(PATS[i][0],PATS[i][1]);
    return s.replace(RUN,function(r){return trRun(r);}).replace(/،/g,',').replace(/؟/g,'?');
  }
  var st=document.createElement('style');
  st.textContent='.l-ar{display:none}html.lang-en .l-ar{display:inline}html.lang-en .l-en{display:none}html.lang-en .tile .tn,html.lang-en .agcard .meta em,html.lang-en .agcard .meta span,html.lang-en .brrow small,html.lang-en .mitem .mn,html.lang-en .mitem .mi,html.lang-en .line .ln b,html.lang-en .ocard .r2,html.lang-en .iname,html.lang-en .acc div>span{text-align:left}html.lang-en .line .lp{text-align:right}html.lang-en h2 small{display:none}html.lang-en .lhero h1{max-width:46%}html.lang-en .step{flex-direction:row-reverse}html.lang-en .iconbtn svg,html.lang-en .row-link svg{transform:scaleX(-1)}html.lang-en .iing,html.lang-en .items .nt,html.lang-en .cust .ph,html.lang-en .sum b{text-align:left}html.lang-en .items .r{justify-content:flex-start;flex-direction:row-reverse;text-align:left}html.lang-en .sw::after{right:auto;left:4px}html.lang-en .onl.on .sw::after{transform:translateX(24px)}.langlink{background:none;border:1px solid currentColor;border-radius:99px;padding:6px 14px;font:inherit;font-size:13px;font-weight:600;color:inherit;opacity:.85;cursor:pointer}';
  (document.head||document.documentElement).appendChild(st);
  window.RQLang={
    lang:lang, t:function(s){return lang==='en'?tr(s):s;},
    set:function(l){try{localStorage.setItem(KEY,l);}catch(e){}location.reload();},
    toggle:function(){this.set(lang==='en'?'ar':'en');}
  };
  /* language buttons: any element with data-lang-toggle */
  document.addEventListener('click',function(e){var b=e.target&&e.target.closest&&e.target.closest('[data-lang-toggle]');if(b){e.preventDefault();window.RQLang.toggle();}},true);
  if(lang!=='en'){return;}

  var html=document.documentElement;
  html.setAttribute('lang','en');html.setAttribute('dir','ltr');html.classList.add('lang-en');
  var ATTRS=['placeholder','aria-label','title','alt'];
  var SKIP={SCRIPT:1,STYLE:1,NOSCRIPT:1};
  function doNode(n){
    if(n.nodeType===3){var v=n.nodeValue;if(/[؀-ۿ]/.test(v)){var t=tr(v);if(t!==v)n.nodeValue=t;}return;}
    if(n.nodeType!==1||SKIP[n.nodeName]||n.hasAttribute('data-no-tr'))return;
    for(var i=0;i<ATTRS.length;i++){var a=n.getAttribute(ATTRS[i]);if(a&&/[؀-ۿ]/.test(a))n.setAttribute(ATTRS[i],tr(a));}
    if(n.nodeName==='INPUT'&&(n.type==='button'||n.type==='submit')&&/[؀-ۿ]/.test(n.value))n.value=tr(n.value);
    if(n.getAttribute('dir')==='rtl'&&!n.hasAttribute('data-keep-dir'))n.setAttribute('dir','ltr');
    if(n.nodeName==='TEXTAREA')return;
    for(var c=n.firstChild;c;c=c.nextSibling)doNode(c);
  }
  function title(){if(/[؀-ۿ]/.test(document.title))document.title=tr(document.title);}
  var mo=new MutationObserver(function(ms){
    for(var i=0;i<ms.length;i++){var m=ms[i];
      if(m.type==='characterData')doNode(m.target);
      else if(m.type==='attributes')doNode(m.target);
      else for(var j=0;j<m.addedNodes.length;j++)doNode(m.addedNodes[j]);}
    title();
  });
  function start(){doNode(document.body);title();
    mo.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:ATTRS.concat(['dir'])});}
  if(document.body)start();else document.addEventListener('DOMContentLoaded',start);
  var oc=window.confirm,oa=window.alert;
  window.confirm=function(m){return oc.call(window,tr(String(m)));};
  window.alert=function(m){return oa.call(window,tr(String(m)));};
})();
