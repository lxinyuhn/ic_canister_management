import { canister_manager } from "../../declarations/canister_manager";

let wasmBuff = null;

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


document.querySelector("form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const button = e.target.querySelector("button");

  const name = document.getElementById("name").value.toString();

  button.setAttribute("disabled", true);

  // Interact with foo actor, calling the greet method
  const greeting = await canister_manager.uploadWasm(name, wasmBuff);

  button.removeAttribute("disabled");

  document.getElementById("greeting").innerText = greeting;

  return false;
});
