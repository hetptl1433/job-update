const STATUSES = ["Interview Requested","Interview Scheduled","Interview Completed","Assessment / Next Round","Awaiting Response","Offer Received","Offer Accepted / Active","Rejected","Withdrawn","Need Status Update"];
const PRIORITIES = ["High","Medium","Low"];
const STAGES = ["Recruiter Screen","One-way Video","Hiring Manager Interview","Final Interview","Technical Assessment","Offer / Onboarding","Unknown"];
const FILTERS = ["All","Active","Offers","Closed","Needs update"];
const CLOSED = ["Rejected","Withdrawn","Offer Accepted / Active"];
const OFFERS = ["Offer Received","Offer Accepted / Active"];

let interviews = [];
let filter = "All";
let search = "";
let editingId = null;
let syncState = "loading";
let updatedAt = null;
let toastTimer;

const $ = (id) => document.getElementById(id);
const form = $("editForm");

const iconPaths = {
  search:'<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', plus:'<path d="M12 5v14M5 12h14"/>',
  download:'<path d="M12 3v12m0 0 4-4m-4 4-4-4"/><path d="M5 19h14"/>', upload:'<path d="M12 21V9m0 0 4 4m-4-4-4 4"/><path d="M5 5h14"/>',
  save:'<path d="M5 4h12l2 2v14H5z"/><path d="M8 4v6h8V4M8 20v-6h8v6"/>', edit:'<path d="m4 20 4.5-1 10-10-3.5-3.5-10 10z"/><path d="m13.5 6.5 3.5 3.5"/>',
  close:'<path d="m6 6 12 12M18 6 6 18"/>', external:'<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 13v7H4V6h7"/>',
  briefcase:'<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V4h8v3M3 12h18"/>', clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  check:'<path d="m5 12 4 4L19 6"/>', alert:'<path d="M12 4 3 20h18z"/><path d="M12 9v4m0 3h.01"/>', chart:'<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  trash:'<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13"/>', lock:'<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>'
};
function icon(name,size=18){return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name]||''}</svg>`;}
function hydrateIcons(){document.querySelectorAll('[data-icon]').forEach(el=>el.innerHTML=icon(el.dataset.icon));}
function escapeHtml(value){return String(value ?? '').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
function normalizeDate(value){if(!value)return ''; if(typeof value==='number'&&window.XLSX){const d=XLSX.SSF.parse_date_code(value);return d?`${d.y}-${String(d.m).padStart(2,'0')}-${String(d.d).padStart(2,'0')}`:'';} const parsed=new Date(String(value));return Number.isNaN(parsed.getTime())?String(value).slice(0,10):parsed.toISOString().slice(0,10);}
function formatDate(value){if(!value)return '—';const [y,m,d]=String(value).slice(0,10).split('-').map(Number);return new Intl.DateTimeFormat('en-US',{month:'short',day:'numeric',year:'numeric'}).format(new Date(y,m-1,d));}
function followUpState(item){if(CLOSED.includes(item.status))return 'closed';if(!item.followUpDate)return 'missing';const today=new Date();today.setHours(0,0,0,0);const due=new Date(`${item.followUpDate}T00:00:00`);const diff=Math.round((due-today)/86400000);if(diff<0)return 'overdue';if(diff===0)return 'today';if(diff<=3)return 'soon';return 'upcoming';}
function statusClass(status){if(OFFERS.includes(status))return 'status status-success';if(status==='Rejected'||status==='Withdrawn')return 'status status-danger';if(status==='Need Status Update')return 'status status-warning';return 'status status-info';}
function metrics(){const offers=interviews.filter(i=>OFFERS.includes(i.status)).length;const rejected=interviews.filter(i=>i.status==='Rejected').length;const active=interviews.filter(i=>!CLOSED.includes(i.status)&&i.status!=='Need Status Update').length;const needsAttention=interviews.filter(i=>['overdue','today','missing'].includes(followUpState(i))||i.status==='Need Status Update').length;return{total:interviews.length,offers,rejected,active,needsAttention};}
function setSync(state){syncState=state;const indicator=$("syncIndicator");indicator.className=`sync-indicator ${state}`;$("syncText").textContent=state==='cloud'?'Cloud synced':state==='local'?'Device storage':state==='saving'?'Saving':state==='error'?'Sync issue':'Loading';$("storageCopy").textContent=state==='cloud'?'Online edits are stored in Vercel Blob.':'Changes are stored on this device until Vercel Blob is connected.';$("saveButton").disabled=state==='saving';$("saveButton").innerHTML=icon('save')+(state==='saving'?' Saving…':' Save changes');}
function showToast(message){clearTimeout(toastTimer);const el=$("toast");el.textContent=message;el.hidden=false;toastTimer=setTimeout(()=>el.hidden=true,3400);}
function render(){renderMetrics();renderFilters();renderTable();}
function renderMetrics(){const m=metrics();const cards=[['Total opportunities',m.total,'Interview calls tracked','blue','briefcase'],['Active pipeline',m.active,'Still moving or awaiting','violet','clock'],['Offers',m.offers,'Received or accepted','green','check'],['Needs attention',m.needsAttention,'Follow-up or status needed','amber','alert']];$("metricGrid").innerHTML=cards.map(([label,value,detail,tone,ic])=>`<article class="metric-card tone-${tone}"><div class="metric-icon">${icon(ic)}</div><div><p>${label}</p><strong>${value}</strong><small>${detail}</small></div></article>`).join('');$("pipelineCopy").textContent=`${m.rejected} closed as rejected · ${m.offers} offers · ${m.active} active`;const other=Math.max(0,m.total-m.offers-m.active-m.rejected);const pct=n=>m.total?(n/m.total*100):0;$("pipelineBar").innerHTML=`<span class="bar-offers" style="width:${pct(m.offers)}%"></span><span class="bar-active" style="width:${pct(m.active)}%"></span><span class="bar-update" style="width:${pct(other)}%"></span><span class="bar-rejected" style="width:${pct(m.rejected)}%"></span>`;}
function renderFilters(){$("filterTabs").innerHTML=FILTERS.map(f=>`<button class="tab ${filter===f?'active':''}" data-filter="${f}">${f}</button>`).join('');document.querySelectorAll('[data-filter]').forEach(btn=>btn.onclick=()=>{filter=btn.dataset.filter;render();});}
function filteredRows(){const q=search.trim().toLowerCase();const followOrder={overdue:0,today:1,missing:2,soon:3,upcoming:4,closed:5};const priority={High:0,Medium:1,Low:2};return [...interviews].filter(item=>{if(filter==='Active'&&(CLOSED.includes(item.status)||item.status==='Need Status Update'))return false;if(filter==='Offers'&&!OFFERS.includes(item.status))return false;if(filter==='Closed'&&!['Rejected','Withdrawn','Offer Accepted / Active'].includes(item.status))return false;if(filter==='Needs update'&&item.status!=='Need Status Update'&&!['overdue','today','missing'].includes(followUpState(item)))return false;return !q||[item.company,item.role,item.status,item.contact,item.nextAction].join(' ').toLowerCase().includes(q);}).sort((a,b)=>followOrder[followUpState(a)]-followOrder[followUpState(b)]||priority[a.priority]-priority[b.priority]);}
function renderTable(){const rows=filteredRows();$("emptyState").hidden=rows.length>0;$("trackerBody").innerHTML=rows.map(item=>{const due=followUpState(item);const followText=due==='closed'?'Closed':due==='missing'?'Set date':due==='today'?'Due today':due==='overdue'?'Overdue':formatDate(item.followUpDate);return `<tr><td data-label="Company & role"><div class="company-cell"><span class="company-logo">${escapeHtml(item.company.slice(0,2).toUpperCase())}</span><div><strong>${escapeHtml(item.company)}</strong><small>${escapeHtml(item.role)}</small></div></div></td><td data-label="Stage"><span class="stage-text">${escapeHtml(item.stage)}</span><small>${escapeHtml(item.mode||'—')}</small></td><td data-label="Status"><span class="${statusClass(item.status)}">${escapeHtml(item.status)}</span><small class="priority priority-${item.priority.toLowerCase()}">${item.priority} priority</small></td><td data-label="Interview"><strong class="date-text">${formatDate(item.interviewDate)}</strong><small>Invited ${formatDate(item.inviteDate)}</small></td><td data-label="Next action"><span class="action-text">${escapeHtml(item.nextAction||'No next action set')}</span><small>${escapeHtml(item.contact||'No recruiter added')}</small></td><td data-label="Follow-up"><span class="follow-up follow-${due}">${followText}</span></td><td class="edit-cell"><button class="icon-button edit-entry" data-id="${item.id}" aria-label="Edit ${escapeHtml(item.company)}">${icon('edit')}</button></td></tr>`;}).join('');document.querySelectorAll('.edit-entry').forEach(btn=>btn.onclick=()=>openModal(Number(btn.dataset.id)));}
function fillSelect(name,values){form.elements[name].innerHTML=values.map(v=>`<option value="${escapeHtml(v)}">${escapeHtml(v)}</option>`).join('');}
function openModal(id){editingId=id;const existing=interviews.find(i=>i.id===id);const item=existing?{...existing}:{id,company:'',role:'',stage:'Recruiter Screen',inviteDate:new Date().toISOString().slice(0,10),interviewDate:'',status:'Interview Requested',priority:'Medium',nextAction:'',followUpDate:'',contact:'',mode:'',source:'',notes:''};$("modalTitle").textContent=existing?'Update interview':'Add interview';for(const [key,value] of Object.entries(item)){if(form.elements[key])form.elements[key].value=value||'';}$("deleteButton").hidden=!existing;$("sourceButton").hidden=!String(item.source).startsWith('http');$("sourceButton").href=String(item.source).startsWith('http')?item.source:'#';$("modalBackdrop").hidden=false;document.body.style.overflow='hidden';}
function closeModal(){$("modalBackdrop").hidden=true;document.body.style.overflow='';editingId=null;}
function readForm(){const fd=new FormData(form);return{id:editingId,company:String(fd.get('company')||'').trim(),role:String(fd.get('role')||'').trim(),stage:String(fd.get('stage')),inviteDate:String(fd.get('inviteDate')),interviewDate:String(fd.get('interviewDate')),status:String(fd.get('status')),priority:String(fd.get('priority')),nextAction:String(fd.get('nextAction')),followUpDate:String(fd.get('followUpDate')),contact:String(fd.get('contact')),mode:String(fd.get('mode')),source:String(fd.get('source')),notes:String(fd.get('notes'))};}
async function loadData(notify=false){
  const password=$('adminPassword').value||sessionStorage.getItem('interview-admin-password')||'';
  if(password){sessionStorage.setItem('interview-admin-password',password);$('adminPassword').value=password;}
  try{
    const headers=password?{'x-admin-password':password}:{};
    const response=await fetch('/api/tracker',{cache:'no-store',headers});
    const payload=await response.json().catch(()=>({}));
    if(response.status===401){
      const local=localStorage.getItem('interview-tracker-data');
      interviews=local?JSON.parse(local):structuredClone(window.SEED_DATA||[]);
      setSync('local');
      $('storageCopy').textContent='Enter your admin password and press Enter to load the cloud tracker.';
      if(notify)showToast(password?'Incorrect admin password':'Enter the admin password');
      updateLastSync();render();return;
    }
    if(!response.ok)throw new Error(payload.error||'Cloud tracker unavailable');
    const local=localStorage.getItem('interview-tracker-data');
    if(!payload.cloud&&local){interviews=JSON.parse(local);setSync('local');}
    else{interviews=payload.data||[];setSync(payload.cloud?'cloud':'local');updatedAt=payload.updatedAt||null;}
    if(notify)showToast(payload.cloud?'Cloud tracker loaded':'Tracker loaded from this device');
  }catch(error){
    const local=localStorage.getItem('interview-tracker-data');
    interviews=local?JSON.parse(local):structuredClone(window.SEED_DATA||[]);
    setSync('local');
    if(notify)showToast(error.message||'Could not load cloud tracker');
  }
  updateLastSync();render();
}
function updateLastSync(){$("lastSync").textContent=updatedAt?`Last cloud update ${new Date(updatedAt).toLocaleString()}`:'';}
async function saveOnline(){setSync('saving');const password=$("adminPassword").value;if(password)sessionStorage.setItem('interview-admin-password',password);try{const response=await fetch('/api/tracker',{method:'PUT',headers:{'Content-Type':'application/json','x-admin-password':password},body:JSON.stringify(interviews)});const payload=await response.json().catch(()=>({}));if(!response.ok)throw new Error(payload.error||'Cloud save unavailable');localStorage.setItem('interview-tracker-data',JSON.stringify(interviews));updatedAt=payload.updatedAt;setSync('cloud');updateLastSync();showToast('Changes saved online');}catch(error){localStorage.setItem('interview-tracker-data',JSON.stringify(interviews));setSync('local');showToast(`${error.message}. Saved on this device.`);}}
function exportExcel(){const rows=interviews.map(i=>({ID:i.id,Company:i.company,Role:i.role,'Interview Stage':i.stage,'Invite Date':i.inviteDate,'Interview Date':i.interviewDate,'Current Status':i.status,Priority:i.priority,'Next Action':i.nextAction,'Follow-Up Date':i.followUpDate,'Contact / Recruiter':i.contact,'Mode / Location':i.mode,'Source / Evidence':i.source,Notes:i.notes,'Follow-Up Flag':followUpState(i)}));const m=metrics();const summary=[{Metric:'Total interview opportunities',Count:m.total},{Metric:'Offers received / accepted',Count:m.offers},{Metric:'Active pipeline',Count:m.active},{Metric:'Rejected',Count:m.rejected},{Metric:'Needs attention',Count:m.needsAttention}];if(window.XLSX){const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Interview Tracker');XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(summary),'Dashboard');XLSX.writeFile(wb,`Het_Interview_Tracker_${new Date().toISOString().slice(0,10)}.xlsx`);}else{const csv=[Object.keys(rows[0]),...rows.map(Object.values)].map(r=>r.map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(',')).join('\n');downloadBlob(csv,'text/csv',`Het_Interview_Tracker_${new Date().toISOString().slice(0,10)}.csv`);}showToast('Current tracker exported for Excel');}
function downloadBlob(content,type,name){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([content],{type}));a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);}
async function importFile(file){try{let mapped=[];if(file.name.toLowerCase().endsWith('.json')){mapped=JSON.parse(await file.text());}else if(window.XLSX){const wb=XLSX.read(await file.arrayBuffer(),{type:'array'});const sheet=wb.Sheets[wb.SheetNames.includes('Interview Tracker')?'Interview Tracker':wb.SheetNames[0]];const data=XLSX.utils.sheet_to_json(sheet,{defval:''});mapped=data.map((row,index)=>({id:Number(row.ID||index+1),company:String(row.Company||''),role:String(row.Role||''),stage:String(row['Interview Stage']||'Unknown'),inviteDate:normalizeDate(row['Invite Date']),interviewDate:normalizeDate(row['Interview Date']),status:String(row['Current Status']||'Need Status Update'),priority:String(row.Priority||'Medium'),nextAction:String(row['Next Action']||''),followUpDate:normalizeDate(row['Follow-Up Date']),contact:String(row['Contact / Recruiter']||''),mode:String(row['Mode / Location']||''),source:String(row['Source / Evidence']||''),notes:String(row.Notes||'')}));}else throw new Error('Excel library did not load. Try again online or import JSON.');mapped=mapped.filter(i=>i.company||i.role);if(!mapped.length)throw new Error('No interview rows were found');interviews=mapped;render();showToast(`Imported ${mapped.length} records — press Save changes to sync`);}catch(error){showToast(error.message||'Could not read that file');}}

fillSelect('stage',STAGES);fillSelect('status',STATUSES);fillSelect('priority',PRIORITIES);hydrateIcons();
$("searchInput").addEventListener('input',e=>{search=e.target.value;renderTable();});
$("addButton").onclick=()=>openModal(Math.max(0,...interviews.map(i=>Number(i.id)||0))+1);
$("importButton").onclick=()=>$("fileInput").click();
$("fileInput").onchange=e=>{const file=e.target.files[0];if(file)importFile(file);e.target.value='';};
$("exportButton").onclick=exportExcel;$("saveButton").onclick=saveOnline;$("closeModal").onclick=closeModal;$("cancelButton").onclick=closeModal;
$('adminPassword').value=sessionStorage.getItem('interview-admin-password')||'';
$('adminPassword').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();loadData(true);}});
$('adminPassword').addEventListener('change',()=>loadData(true));
$("modalBackdrop").addEventListener('mousedown',e=>{if(e.target===$("modalBackdrop"))closeModal();});
form.addEventListener('submit',e=>{e.preventDefault();const item=readForm();if(!item.company||!item.role){showToast('Company and role are required');return;}const index=interviews.findIndex(i=>i.id===item.id);if(index>=0)interviews[index]=item;else interviews.push(item);closeModal();render();showToast('Tracker updated — press Save changes to sync it');});
$("deleteButton").onclick=()=>{const item=interviews.find(i=>i.id===editingId);if(item&&confirm(`Delete ${item.company}?`)){interviews=interviews.filter(i=>i.id!==editingId);closeModal();render();showToast('Entry removed — press Save changes to sync it');}};
loadData();
