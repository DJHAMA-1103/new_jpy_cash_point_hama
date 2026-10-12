'use strict';
(() => {
  const roles = [{id:'coordinator',name:'총괄',description:'작업 배분 · 인계 · 결과 취합'},{id:'ui',name:'UI / UX',description:'화면 구조 · 사용자 경험'},{id:'developer',name:'개발',description:'기능 구현 · 기술 검토'},{id:'reviewer',name:'리뷰 / 테스트',description:'독립 검토 · 동작 검증'}];
  const labels = {running:'실행 중',queued:'대기 중',pending:'대기 중',idle:'대기',waiting:'대기',offline:'연결 없음',completed:'실행 완료',done:'실행 완료',blocked:'진행 불가',failed:'실패',error:'오류',cancelled:'취소됨',canceled:'취소됨',cancelling:'취소 중',starting:'시작 중',stopped:'중지'};
  const $ = id => document.getElementById(id);
  let snapshot = {agents:[],tasks:[],messages:[],events:[]}, token = null, online = false, sending = false, selected = null, lastSync = null, previous = '';
  const cards = new Map();
  function node(tag,text,className) {const e=document.createElement(tag);if(text!==undefined&&text!==null)e.textContent=String(text);if(className)e.className=className;return e;}
  const name=id=>roles.find(role=>role.id===id)?.name||({user:'사용자',system:'시스템'}[id])||id||'미지정';
  function date(value) {if(!value)return '시각 미확인';const d=new Date(typeof value==='number'&&value<1e12?value*1000:value);return Number.isNaN(d.getTime())?'시각 미확인':d.toLocaleString('ko-KR',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'});}
  const pill=status=>node('span',labels[status]||status||'미확인','pill '+(Object.hasOwn(labels,status)?status:''));
  function initializeCards(){
    for(const role of roles){
      const card=node('article',null,'agent-card');card.dataset.role=role.id;
      const header=node('div',null,'agent-header'),state=pill('offline');header.append(node('strong',role.name),state);
      const scene=node('div',null,'scene');scene.setAttribute('aria-hidden','true');
      const avatar=node('div',null,'avatar');avatar.append(node('div',null,'head'),node('div',null,'torso'));scene.append(avatar,node('div',null,'desk'),node('div',null,'monitor'));
      const body=node('div',null,'agent-body'),summary=node('p',role.description,'agent-summary'),meta=node('div','실행 상태 미확인','agent-meta'),button=node('button','메시지 작성 ↗','agent-button');
      button.type='button';button.setAttribute('aria-label',role.name+'에게 메시지 작성');button.addEventListener('click',()=>{$('recipient').value=role.id;$('body').focus();});
      body.append(summary,meta,button);card.append(header,scene,body);$('agents').append(card);cards.set(role.id,{card,state,summary,meta});
    }
  }
  function updateConnection(){
    $('connection').textContent=online?(snapshot.server?.mode==='test'?'● 테스트 서버 연결됨':'● 실제 실행 서버 연결됨'):'● 연결 끊김';$('connection').className='pill '+(online?'live':'offline');
    $('last-sync').textContent=lastSync?'마지막 동기화 '+date(lastSync):'아직 동기화하지 않았습니다';$('send').disabled=!online||!token||sending;
    document.getElementById('execution-mode').textContent = online ? (snapshot.server?.mode==='test'?'테스트 실행기 · 실제 모델 실행이 아닙니다. ':'실제 Codex 실행 · ') + (snapshot.server?.sandbox==='workspace-write'?'UI·개발은 배정된 파일 수정 가능 / 총괄·리뷰는 읽기 전용':'모든 역할 읽기 전용') + ' · 작업마다 새 실행, 최근 대화 일부를 전달합니다. 보고 종합은 후속 작업 요청이 필요합니다.' : '연결이 끊겨 현재 실행 상태와 권한을 확인할 수 없습니다.';
    for(const role of roles){
      const v=cards.get(role.id),agent=snapshot.agents.find(a=>a.id===role.id),status=online?(agent?.status||'offline'):'offline';
      v.card.classList.toggle('running',status==='running');v.state.textContent=online?(labels[status]||status):'상태 미확인';v.state.className='pill '+(Object.hasOwn(labels,status)?status:'');
      v.summary.textContent=agent?.summary||role.description;v.summary.title=agent?.summary||role.description;
      v.meta.textContent=online&&agent?(agent.pid?'실행 PID '+agent.pid:'실행 PID 없음')+(agent.lastSeen?' · 최근 '+date(agent.lastSeen):''):(lastSync?'연결 끊김 · 마지막 수신 내용':'서버 연결 후 확인');
    }
  }
  async function request(path,options={}){
    const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),8000);
    try {const response=await fetch(path,{...options,signal:controller.signal,cache:'no-store'});const data=await response.json();if(!response.ok)throw new Error(data.error||data.message||'요청 실패 ('+response.status+')');return data;}
    finally {clearTimeout(timeout);}
  }
  async function post(path,body){if(!token)throw new Error('인증 정보를 가져오지 못했습니다.');return request(path,{method:'POST',headers:{'Content-Type':'application/json','X-Orchestra-Token':token},body:JSON.stringify(body)});}
  function renderTasks(){
    const list=$('tasks'), focused=document.activeElement, focusKey=list.contains(focused)?focused.dataset.focusKey:null, scroll=list.scrollTop;list.replaceChildren();const tasks=snapshot.tasks.slice().sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt));$('task-count').textContent=tasks.length+'개';
    if(!tasks.length)list.append(node('p','아직 작업이 없습니다. 왼쪽에서 첫 작업 요청을 보내세요.','empty'));
    for(const task of tasks){
      const row=node('div',null,'task-row'+(task.id===selected?' selected':'')),open=node('button',null,'task-open');open.type='button';open.dataset.focusKey='open-'+task.id;open.append(node('strong',task.body||'내용 없는 작업'),node('small',name(task.to)+' · '+date(task.createdAt)));open.setAttribute('aria-pressed',String(task.id===selected));open.addEventListener('click',()=>{selected=task.id;renderTasks();renderDetail();});row.append(open,pill(task.status));
      if(['queued','pending','running'].includes(task.status)){
        const cancel=node('button','취소','cancel');cancel.type='button';cancel.dataset.focusKey='cancel-'+task.id;cancel.disabled=!online;cancel.setAttribute('aria-label',name(task.to)+' 작업 취소');
        cancel.addEventListener('click',async()=>{cancel.disabled=true;try{await post('/api/tasks/'+encodeURIComponent(task.id)+'/cancel',{});$('form-status').textContent='취소 요청을 전달했습니다.';}catch(error){$('form-status').textContent=error.message;cancel.disabled=!online;}});row.append(cancel);
      }list.append(row);
    }
    list.scrollTop=scroll;
    if(focusKey){const target=Array.from(list.querySelectorAll('button')).find(button=>button.dataset.focusKey===focusKey);if(target)target.focus({preventScroll:true});}
  }
  function renderDetail(){
    const c=$('detail'),task=snapshot.tasks.find(t=>t.id===selected);c.replaceChildren();if(!task){c.append(node('p','목록에서 작업을 선택하면 결과와 오류를 확인할 수 있습니다.','empty'));return;}
    c.append(node('div',name(task.from)+' → '+name(task.to)+' · '+(labels[task.status]||task.status)+' · '+date(task.updatedAt||task.createdAt),'detail-meta'));
    for(const [label,text] of [['작업 ID',task.id],['요청 내용',task.body],['실행 결과',task.result],['오류',task.error]])if(text!==undefined&&text!==null&&text!=='')c.append(node('div',label,'detail-label'),node('pre',typeof text==='string'?text:JSON.stringify(text,null,2),label==='오류'?'error-text':''));
    if(!task.result&&!task.error)c.append(node('p','아직 결과가 수신되지 않았습니다.','empty'));
  }
  function renderTimeline(){
    const filter=$('role-filter').value,c=$('timeline');c.replaceChildren();
    const entries=snapshot.messages.map(m=>({...m,entryType:'message'})).concat(snapshot.events.map(e=>({...e,entryType:'event'}))).filter(e=>filter==='all'||e.role===filter||e.from===filter||e.to===filter).sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt)).slice(0,150);
    if(!entries.length)c.append(node('p',filter==='all'?'아직 기록이 없습니다. 실제 메시지와 실행 이벤트가 여기에 쌓입니다.':'이 에이전트의 기록이 아직 없습니다.','empty'));
    for(const e of entries){const row=node('div',null,'event'),content=node('div'),heading=node('div',null,'event-heading');heading.append(node('strong',e.entryType==='message'?name(e.from)+' → '+name(e.to):name(e.role)),node('span',e.entryType==='message'?(e.kind==='task'?'작업 요청':'정보 전달'):(labels[e.kind]||e.kind||'이벤트'),'event-type'));content.append(heading,node('p',e.body||e.text||''));row.append(node('time',date(e.createdAt)),content);c.append(row);}
  }
  function render(){$('running-count').textContent=snapshot.tasks.filter(t=>t.status==='running').length;$('queued-count').textContent=snapshot.tasks.filter(t=>['queued','pending'].includes(t.status)).length;$('completed-count').textContent=snapshot.tasks.filter(t=>['completed','done'].includes(t.status)).length;renderTasks();renderDetail();renderTimeline();}
  async function poll(){
    try{if(!token)token=(await request('/api/token')).token;const state=await request('/api/state',{headers:{'X-Orchestra-Token':token}});for(const key of ['agents','tasks','messages','events'])if(!Array.isArray(state[key]))throw new Error('서버 응답 형식이 올바르지 않습니다.');snapshot=state;online=true;lastSync=new Date().toISOString();const serialized=JSON.stringify(state);if(serialized!==previous){previous=serialized;render();}}
    catch(error){online=false;token=null;previous='';$('connection').title=error.message;document.querySelectorAll('.cancel').forEach(b=>{b.disabled=true;});}
    finally{updateConnection();setTimeout(poll,1000);}
  }
  function updateKind(){const task=$('kind').value==='task';$('kind-help').textContent=task?'작업 요청을 보내면 실제 Codex가 실행되며 계정 사용량이 발생할 수 있습니다.':'정보 전달은 받은 메시지에 기록됩니다. 모델을 실행하거나 즉시 답변을 생성하지 않습니다.';$('send').textContent=task?'작업 요청 보내기 ↗':'정보 전달하기 ↗';}
  const templates={status:'현재 담당 작업의 진행상황을 보고하세요. 완료한 내용, 실제 검증 결과, 막힌 사항, 다음 작업을 구분하고 확인하지 못한 것은 미확인으로 표시하세요.',handoff:'완료한 결과를 다음 담당 에이전트에게 전달하세요. 전달 대상, 산출물 경로, 변경 범위, 검증 근거, 남은 문제를 명시하세요. 같은 파일의 동시 수정을 피하세요.',review:'지정한 산출물을 독립적으로 다시 검토하세요. 검토 대상: [파일 또는 작업 ID]. 문제 위치, 재현 근거, 영향, 수정 필요성을 보고하고 미실행 검증은 구분하세요.'};
  document.querySelectorAll('[data-template]').forEach(b=>b.addEventListener('click',()=>{$('body').value=templates[b.dataset.template];$('kind').value='task';updateKind();$('body').focus();}));
  $('kind').addEventListener('change',updateKind);$('role-filter').addEventListener('change',renderTimeline);
  $('message-form').addEventListener('submit',async event=>{event.preventDefault();const body=$('body').value.trim(), kind=$('kind').value, to=$('recipient').value;if(!body||sending||!online)return;sending=true;updateConnection();$('form-status').textContent='전달 중…';try{await post('/api/messages',{from:'user',to,body,kind});if($('body').value.trim()===body)$('body').value='';$('form-status').textContent=kind==='task'?'작업 요청을 접수했습니다. 목록에서 실행 상태를 확인하세요.':'정보를 전달했습니다. 모델 실행은 요청하지 않았습니다.';}catch(error){$('form-status').textContent='전달 실패: '+error.message;}finally{sending=false;updateConnection();}});
  initializeCards();poll();
})();
