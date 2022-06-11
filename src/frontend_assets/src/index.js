import {Actor, HttpAgent} from "@dfinity/agent";
import {AuthClient} from "@dfinity/auth-client"

// import { canisterManager } from "../../declarations/canister_manager";
import { idlFactory, canisterId, createActor } from "../../declarations/canister_manager";

let wasmBuff = null;
let canisterManager = null;
const days = BigInt(1);
const hours = BigInt(24);
const nanoseconds = BigInt(3600000000000);

const init = async () =>{
  const authClient = await AuthClient.create()
  if (await authClient.isAuthenticated){
    handleAuthenticated(authClient);
  }

  const signOutBtn = document.getElementById("signoutBtn");
  signOutBtn.onclick = async () => {
    console.log("logout:")
    await authClient.logout();
  };

  
  const loginBtn = document.getElementById("loginBtn");
  loginBtn.onclick = async () => {
    await authClient.login({
      onSuccess: async () => {
        handleAuthenticated(authClient);
      },
      identityProvider: "http://rwlgt-iiaaa-aaaaa-aaaaa-cai.localhost:8000/#authorize",
      maxTimeToLive: days * hours * nanoseconds,
    })
  };
}

const handleAuthenticated = async (authClient) => {
  const identity = await authClient.getIdentity();
  // canisterManager = createActor(canisterId, {identity})
  canisterManager = createActor(canisterId, {
    agentOptions: {
      identity,
    }
  })
  // const whoami_actor = createActor(canisterId, {
  //   agentOptions: {
  //     identity,
  //   },
  // });  

  // Actor.createActor(idlFactory, {
  //   agent: new HttpAgent({
  //     identity,
  //   }),
  //   canisterId,
  // });
  console.log("identity:", identity);
  // const loginDiv = document.getElementById("loginDiv");
  // const logoutDiv = document.getElementById("logoutDiv");
  const principalId = document.getElementById("principalId");
  const proposalsDiv = document.getElementById("proposalsDiv");
  
  // loginDiv.setAttribute("style","display: none;");
  // logoutDiv.setAttribute("style","display: block;");
  principalId.innerText = identity.getPrincipal();
  proposalsDiv.setAttribute("style","display: block;");
  //获取canisters
  const canisters = await canisterManager.list_canisters();

  console.log("canisters:", canisters)
  if (canisters) {
    const canister_id = document.getElementById("canister_id");
    canister_id.options.length=0;  
    for (let key in canisters){
      canister_id.options.add(new Option(canisters[key],canisters[key]));
    }    
  }  

  const members = await canisterManager.list_members();
  if (members) {
    const table = document.getElementById("members");
    let tableHtml = `
    <table class="table">
      <tr>
        <td class="col-md-7">principal_id</td>
      </tr>  
    `;  
    for (let index in members){
      const member = members[index]
      console.log("member:", member); 
      tableHtml += `
        <tr>
          <td>${member}</td>
        </tr>          
      `;
    }
    
    tableHtml += '</table>';
    table.innerHTML = tableHtml;
  }  


  const warns = await canisterManager.list_wasms();
  console.log("warns:", warns);  
  if (warns) {
    const ver = document.getElementById("ver");
    ver.options.length=0;  
    for (let key in warns){
      console.log("key:", key,warns[key]); 
      ver.options.add(new Option(warns[key],warns[key]));
    }    
  }
  const M = await canisterManager.get_m();
  console.log("M:", M);
  const proposals = await canisterManager.list_proposals();
  console.log("proposals:", proposals);
  if (proposals) {
    const table = document.getElementById("table");
    let tableHtml = `
    <table class="table">
      <tr>
        <td class="col-md-1">#</td>
        <td class="col-md-7">title</td>
        <td class="col-md-2">progress</td>
        <td class="col-md-1">vote</td>
        <td class="col-md-1">action</td>
      </tr>    
    `;  
    for (let index in proposals){
      const proposal = proposals[index]
      console.log("proposal:", proposal); 
      tableHtml += `
        <tr>
          <td>${proposal.id}</td>
          <td>${proposal.payload.method}/${proposal.payload.canister_id}/${proposal.payload.ver}/${proposal.payload.principal_id}</td>
          <td>      
            <div class="progress">
              <div class="progress-bar" role="progressbar" aria-valuenow="2" aria-valuemin="0" aria-valuemax="100" style="min-width: 2em; width: ${
               ("accepted" in proposal.state || "open" in proposal.state) ? proposal.voters_yes.length* 100 / members.length : 0
              }%;">
                ${ ("accepted" in proposal.state || "open" in proposal.state) ? (proposal.voters_yes.length/members.length * 100).toFixed(0) : 0}%
              </div>
            </div>
          </td>
          <td>
            <button type="button" class="btn btn-primary btn-sm" id="proposalOk${proposal.id}">赞成</button>
            <button type="button" class="btn btn-primary btn-sm" id="proposalNo${proposal.id}">反对</button>
          </td>
          <td><button type="button" class="btn btn-danger btn-sm" id="execute${proposal.id}">执行</button></td>
        </tr>          
      `;      
    }
    
    tableHtml += '</table>';
    table.innerHTML = tableHtml;
    for (let index in proposals){
      const proposal = proposals[index]
      const proposalOkEl = document.getElementById(`proposalOk${proposal.id}`);
      proposalOkEl.onclick = async (e) =>{
        e.preventDefault();
        await canisterManager.vote(proposal.id, true);
        console.log("vote:", proposal.id, true)
        handleAuthenticated(authClient);
      }
      const proposalNoEl = document.getElementById(`proposalNo${proposal.id}`);
      proposalNoEl.onclick = async (e) =>{
        e.preventDefault();
        await canisterManager.vote(proposal.id, false);
        console.log("vote:", proposal.id, false)
        handleAuthenticated(authClient);
      }    
      const proposalExecEl = document.getElementById(`execute${proposal.id}`);
      proposalExecEl.onclick = async (e) =>{
        e.preventDefault();
        const res = await canisterManager.execute_proposal(proposal.id);
        console.log("execute_proposal:", proposal.id, res)
        handleAuthenticated(authClient);
      }        
    }
  }  



  document.getElementById("wasm").addEventListener("change", async (e) => {
    e.preventDefault();
    console.log("e:",e)
    var file = e.target.files[0];
    var reader = new FileReader();//new一个FileReader实例
    reader.onload = function(){
      console.log("this.result:",this.result);
      wasmBuff = Array.from(new Uint8Array(this.result))
    }
    reader.readAsArrayBuffer(file);

    return false;
  });


  document.getElementById("form1").addEventListener("submit", async (e) => {
    e.preventDefault();
    const button = e.target.querySelector("button");
    const name = document.getElementById("name").value.toString();
    button.setAttribute("disabled", true);
    // Interact with foo actor, calling the greet method
    const greeting = canisterManager ? await canisterManager.uploadWasm(name, wasmBuff): "";
    button.removeAttribute("disabled");
    document.getElementById("greeting").innerText = greeting;
    handleAuthenticated(authClient);
    return false;
  });

  document.getElementById("form2").addEventListener("submit", async (e) => {
    e.preventDefault();
    const method = document.getElementById("method").value.toString();
    const canister_id = document.getElementById("canister_id").value.toString();
    const ver = document.getElementById("ver").value.toString();
    const principal_id = document.getElementById("principal_id").value.toString();
    
    await canisterManager.submit_proposal(method, canister_id?[canister_id]:[], ver?[ver]:[], principal_id?[principal_id]:[]);
    handleAuthenticated(authClient);
    return false;
  });

}

init();