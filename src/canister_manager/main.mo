import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import IC "./ic";
import Principal "mo:base/Principal";

actor class () = self {
    // stable var wasms = HashMap<Text, Blob>();
    let wasms = HashMap.HashMap<Text,Blob>(3, Text.equal, Text.hash);

    public func uploadWasm(name : Text, wasm: Blob) : async Text {
        wasms.put(name, wasm);
        return "upload succ, name:" # name # ".";
    };

    public func getWasm(name : Text) : async ?Blob {
        wasms.get(name);
    };    

    public func create_canister(): async IC.canister_id{
        let settings = {
            freezing_threshold = null;
            controllers = ?[Principal.fromActor(self)];
            memory_allocation = null;
            compute_allocation = null;
        };

        let ic: IC.Self = actor("aaaaa-aa");
        let result = await ic.create_canister({settings = ?settings});
        result.canister_id
    };

    public func install_code(canister_id: Text, wasm_name: Text): async (){
        let wasm_module = wasms.get(wasm_name);
        switch(wasm_module){
            case (null){

            };
            case (?wasm){
                let ic: IC.Self = actor("aaaaa-aa");
                let result = await ic.install_code({
                    arg = [];
                    wasm_module = Blob.toArray(wasm);
                    mode = #install;
                    canister_id = Principal.fromActor(actor(canister_id));    
                });
            };
        };
    };

    public func stop_canister(canister_id: Text): async (){
        let ic: IC.Self = actor("aaaaa-aa");
        await ic.stop_canister({
            canister_id = Principal.fromActor(actor(canister_id));    
        });        
    };

    public func delete_canister(canister_id: Text): async (){
        let ic: IC.Self = actor("aaaaa-aa");
        await ic.delete_canister({
            canister_id = Principal.fromActor(actor(canister_id));    
        });            
    };    

};
