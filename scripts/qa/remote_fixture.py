from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time
EVENTS=[]
PAGE_STATE=None
def json_safe(value):
 if isinstance(value,str): return value.encode('utf-16-le','surrogatepass').decode('utf-16-le','replace')
 if isinstance(value,list): return [json_safe(item) for item in value]
 if isinstance(value,dict): return {key:json_safe(item) for key,item in value.items()}
 return value
HTML='''<!doctype html><meta charset="utf-8"><title>AetherScreens QA</title><style>body{font:22px system-ui;background:#eef5ff;margin:36px}button,input,textarea{font:24px system-ui;padding:16px}button{background:#166aff;color:white;border:0;border-radius:12px}#scroll{height:240px;overflow:auto;background:white;margin-top:24px}#drag{position:absolute;left:650px;top:140px;background:#00a8a0;color:white;padding:36px;cursor:grab}#ball{position:absolute;top:430px;border-radius:30px;background:#166aff;width:60px;height:60px}#clock{font:28px monospace}#response{position:fixed;right:80px;bottom:40px;width:100px;height:100px;background:#eef5ff}#result{white-space:pre-wrap}h1{margin:0 0 20px}</style><h1>AetherScreens Functional QA</h1><button id="click">Click test: 0</button> <button id="reset">Reset counters</button><p><textarea id="input" placeholder="Keyboard / Unicode / paste test" rows="2" cols="38"></textarea></p><div id="drag">Drag me</div><div id="clock"></div><div id="ball"></div><div id="scroll">'''+''.join('<p>Scroll row '+str(i)+'</p>' for i in range(60))+'''</div><div id="response"></div><pre id="result"></pre><script>const click=document.getElementById("click"),reset=document.getElementById("reset"),input=document.getElementById("input"),scroll=document.getElementById("scroll"),drag=document.getElementById("drag"),clock=document.getElementById("clock"),ball=document.getElementById("ball"),result=document.getElementById("result"),response=document.getElementById("response");let count=0;function log(t,d={}){result.textContent=t+' '+JSON.stringify(d);fetch('/event',{method:'POST',body:JSON.stringify({type:t,data:d,time:performance.now()})})};click.onclick=()=>{click.textContent='Click test: '+(++count);response.style.background=count%2?'#ffe9cc':'#eef5ff';log('click',{count})};reset.onclick=()=>{count=0;log('reset')};input.oninput=()=>log('input',{value:input.value});input.onkeydown=e=>log('key',{key:e.key,code:e.code,meta:e.metaKey,ctrl:e.ctrlKey,alt:e.altKey,shift:e.shiftKey});input.onpaste=e=>log('paste',{value:e.clipboardData.getData('text')});document.onmousedown=e=>log("mouse-down",{x:e.clientX,y:e.clientY,button:e.button});document.oncontextmenu=e=>{e.preventDefault();log('right-click',{x:e.clientX,y:e.clientY})};scroll.onscroll=()=>log('scroll',{top:scroll.scrollTop});let down=false;drag.onmousedown=e=>{down=true;log('drag-start')};document.onmouseup=e=>{if(down)log('drag-end',{x:e.clientX,y:e.clientY});down=false};document.onmousemove=e=>{if(down){drag.style.left=e.clientX-50+'px';drag.style.top=e.clientY-30+'px'}};function frame(t){clock.textContent='Animation '+(t/1000).toFixed(3)+' seconds';ball.style.left=(500+350*Math.sin(t/700))+'px';requestAnimationFrame(frame)}requestAnimationFrame(frame);log('ready');</script>'''
HTML += '''<script>
input.addEventListener('copy',()=>log('copy',{value:input.value.slice(input.selectionStart,input.selectionEnd)}));
function reportPageState() {
 const rects={};
 for (const id of ['click','input','scroll','drag','response']) {
  const r=document.getElementById(id).getBoundingClientRect();
  rects[id]={x:r.x,y:r.y,width:r.width,height:r.height};
 }
 fetch('/event',{method:'POST',body:JSON.stringify({type:'page-state',data:{
  focused:document.hasFocus(),visible:document.visibilityState==='visible',
  screenX:window.screenX,screenY:window.screenY,
  outerWidth:window.outerWidth,outerHeight:window.outerHeight,
  innerWidth:window.innerWidth,innerHeight:window.innerHeight,
  pixelRatio:window.devicePixelRatio,rects
 }})});
}
reportPageState();
setInterval(reportPageState,2000);
window.addEventListener('focus',reportPageState);
window.addEventListener('blur',reportPageState);
document.addEventListener('visibilitychange',reportPageState);
</script>'''
class H(BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_GET(self):
  value=EVENTS if self.path=='/events' else PAGE_STATE
  is_json=self.path in ('/events','/page-state')
  payload=json.dumps(json_safe(value)).encode() if is_json else HTML.encode()
  self.send_response(200);self.send_header('Content-Type','application/json' if is_json else 'text/html');self.end_headers();self.wfile.write(payload)
 def do_POST(self):
  global PAGE_STATE
  event=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))));event['serverTime']=time.time()
  value=event.get('data',{}).get('value')
  if isinstance(value,str):
   raw=value.encode('utf-16-le','surrogatepass')
   event['data']['utf16Units']=[int.from_bytes(raw[i:i+2],'little') for i in range(0,len(raw),2)]
   event['data']['valueHasUnpairedSurrogate']=value!=json_safe(value)
  if event.get('type')=='page-state': PAGE_STATE=event
  else:
   EVENTS.append(event)
   del EVENTS[:-4096]
  self.send_response(200);self.end_headers()
if __name__=='__main__': HTTPServer(('127.0.0.1',8766),H).serve_forever()
