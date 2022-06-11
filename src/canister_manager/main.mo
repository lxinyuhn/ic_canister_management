import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import HashMap "mo:base/HashMap";
import IC "./ic";
import Int "mo:base/Int";
import List "mo:base/List";
import M "mo:base/Float";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Trie "mo:base/Trie";

shared(msg) actor class () = self {
    
    public type Proposal = {
        id : Nat;
        voters_yes : [Text];
        state : ProposalState;
        timestamp : Int;
        proposer : Principal;
        payload : ProposalPayload;
    };

    public type ProposalPayload = {
        method : Text;
        canister_id : ?Text;
        ver : ?Text;
        principal_id: ?Text;
    };

    public type ProposalState = {
        #failed: Text;
        #open;
        #accepted;
        #executing;        
        #succeeded;
        #rejected;
    };
    
    stable var proposal_id_seq = 0;
    stable var proposals =  Trie.empty<Nat, Proposal>();
    stable var canisters: List.List<Text> = List.nil();

    stable var members: List.List<Text> = List.fromArray([
        Principal.toText(msg.caller)
    ]);
    stable var M: Nat = 1;

    let wasms = HashMap.HashMap<Text,Blob>(3, Text.equal, Text.hash);
    // List.fromArray([
    //     "oekem-ngccb-mnhpq-uhrkz-acnw5-vufl5-hn3cy-hj4u3-ng5yb-6jvkv-kqe",
    //     "coerq-x4i4r-sjgmj-dhvgr-iy2dc-3xh7j-nrty6-ewqkn-akvml-xl2kp-oae",
    //     "ew5ay-bc5fc-4pvfl-t3xa5-e6cfa-mx3wd-gxu4c-3qvi5-fb36e-n6yrm-fqe"
    // ]);


    public func uploadWasm(name : Text, wasm: Blob) : async Text {
        wasms.put(name, wasm);
        return "upload succ, name:" # name # ".";
    };

    public func getWasm(name : Text) : async ?Blob {
        wasms.get(name);
    };    

    public query func list_wasms() : async [Text] {
        var wasms_keys: List.List<Text> = List.nil();
        for (key in wasms.keys()){
            wasms_keys := List.push(key, wasms_keys);
        };
        List.toArray(wasms_keys)
    };     

    public query func get_m() :async Nat {
        M
    };    

    public query func list_members() : async [Text] {
        List.toArray(members)
    };   

    func create_canister(): async IC.canister_id {
        let settings = {
            freezing_threshold = null;
            controllers = ?[Principal.fromActor(self)];
            memory_allocation = null;
            compute_allocation = null;
        };

        let ic: IC.Self = actor("aaaaa-aa");
        Cycles.add(1_000_000_000_000);
        let result = await ic.create_canister({settings = ?settings});
        result.canister_id
    };

    func install_code(canister_id: Text, wasm_name: Text): async (){
        let wasm_module = wasms.get(wasm_name);
        switch(wasm_module){
            case null {};
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

    func stop_canister(canister_id: Text): async (){
        let ic: IC.Self = actor("aaaaa-aa");
        await ic.stop_canister({
            canister_id = Principal.fromActor(actor(canister_id));    
        });        
    };

    func delete_canister(canister_id: Text): async (){
        let ic: IC.Self = actor("aaaaa-aa");
        await ic.delete_canister({
            canister_id = Principal.fromActor(actor(canister_id));    
        });            
    };    

    func add_member(principal_id: Text): () {
        members := List.push(principal_id, members);
        M := Nat.div(Nat.mul(List.size(members)-1, 51), 100) + 1;
    };

    func del_member(principal_id: Text): () {
        Debug.print(debug_show(members));
        members := List.filter(members, func (p: Text): Bool {p != principal_id});
        Debug.print(debug_show(members));
    };    

    func proposal_key(t: Nat) : Trie.Key<Nat> {
        return { key = t; hash = Int.hash t };
    };  
    func proposal_get(id : Nat) : ?Proposal {
        Trie.get(proposals, proposal_key(id), Nat.equal)
    };
    func proposal_put(id : Nat, proposal : Proposal) {
        proposals := Trie.put(proposals, proposal_key(id), Nat.equal, proposal).0;
    };

    public shared({caller}) func submit_proposal(method: Text, canister_id: ?Text, ver: ?Text, principal_id: ?Text) : async (?Nat) {
        let payload: ProposalPayload = {
            method;
            canister_id;
            ver;
            principal_id;
        };
        proposal_id_seq := proposal_id_seq + 1;
        
        let proposal_id = proposal_id_seq;

        let proposal : Proposal = {
            id = proposal_id;
            timestamp = Time.now();
            proposer = caller;
            payload;
            state = #open;
            voters_yes = [];
        };
        proposals := Trie.put(proposals, proposal_key(proposal_id), Nat.equal, proposal).0;
        ?proposal_id
    };    

    public query func get_proposal(proposal_id: Nat) : async ?Proposal {
        proposal_get(proposal_id)
    };

    public query func list_proposals() : async [Proposal] {
        Trie.toArray(proposals, func (k:Nat, v:Proposal): Proposal { v })
    };     

    public query func list_canisters() : async [Text] {
        List.toArray(canisters)
    };        

    public shared({caller}) func vote(proposal_id: Nat, pass: Bool) : async Result.Result<ProposalState, Text> {
        let call_account = Principal.toText(caller);
        Debug.print(debug_show(proposal_id));
        Debug.print(debug_show(pass));
        Debug.print(debug_show(call_account));
        switch (proposal_get(proposal_id)) {
            case null { #err("No proposal with ID " # debug_show(proposal_id) # " exists") };
            case (?proposal) {
                var state = proposal.state;
                if (state != #open) {
                    return #err("Proposal " # debug_show(proposal_id) # " is not open for voting");
                };
                
                var voters_yes = proposal.voters_yes;
                let is_member = List.some(members, func (p: Text): Bool {p == call_account});
                
                if (not is_member){
                    return #err("Caller:" # call_account # " is not a member")
                } else {
                    let a: List.List<Text> = List.fromArray(voters_yes);
                    if (not List.some(a, func (p: Text): Bool {p == call_account})){
                        voters_yes := List.toArray(List.push(call_account, a));           
                    } else {
                        return #err("Caller:" # call_account # " has voted")
                    }
                };

                Debug.print(debug_show(voters_yes));

                if (voters_yes.size() >= M) {
                    state := #accepted;
                };                
                let updated_proposal = {
                    id = proposal.id;
                    voters_yes;                              
                    state;
                    timestamp = proposal.timestamp;
                    proposer = proposal.proposer;
                    payload = proposal.payload;
                };
                proposal_put(proposal_id, updated_proposal);      
                #ok(state)          
            };
        };
    };  

    public shared({caller}) func execute_proposal(proposal_id: Nat) : async Result.Result<ProposalState, Text> {
        try {
            switch (proposal_get(proposal_id)) {
                case null { #err("No proposal with ID " # debug_show(proposal_id) # " exists") };
                case (?proposal) {
                    var state = proposal.state;
                    if (state != #accepted){
                        return #err("state err");
                    };
                    let payload = proposal.payload;
                    if (payload.method == "create_canister"){
                        let canister_id = payload.canister_id;
                        state := #executing;
                        proposal_put(proposal_id, {
                            id = proposal.id;
                            voters_yes = proposal.voters_yes;                      
                            state;
                            timestamp = proposal.timestamp;
                            proposer = proposal.proposer;
                            payload = proposal.payload;                            
                        });                                

                        let id = await create_canister();
                        canisters := List.push(Principal.toText(id), canisters);
                        state := #succeeded;
                    } else if (payload.method == "install_code"){
                        switch (payload.canister_id){
                            case null { return #err("Null wasm") };
                            case (?canister_id) {
                                state := #executing;
                                proposal_put(proposal_id, {
                                    id = proposal.id;
                                    voters_yes = proposal.voters_yes;                      
                                    state;
                                    timestamp = proposal.timestamp;
                                    proposer = proposal.proposer;
                                    payload = proposal.payload;                            
                                });                                

                                switch (payload.ver){
                                    case null { return #err("Null wasm") };
                                    case (?ver) {
                                        await install_code(canister_id, ver);
                                    };
                                };
                            };
                        };
                        state := #succeeded;
                    } else if (payload.method == "stop_canister") {
                        switch (payload.canister_id){
                            case null { return #err("Null wasm") };
                            case (?canister_id) {
                                state := #executing;
                                proposal_put(proposal_id, {
                                    id = proposal.id;
                                    voters_yes = proposal.voters_yes;                      
                                    state;
                                    timestamp = proposal.timestamp;
                                    proposer = proposal.proposer;
                                    payload = proposal.payload;                            
                                });                                
                                await stop_canister(canister_id);
                            };
                        };
                        state := #succeeded;
                    }  else if (payload.method == "delete_canister") {
                        switch (payload.canister_id){
                            case null { return #err("Null wasm") };
                            case (?canister_id) {
                                state := #executing;
                                proposal_put(proposal_id, {
                                    id = proposal.id;
                                    voters_yes = proposal.voters_yes;                      
                                    state;
                                    timestamp = proposal.timestamp;
                                    proposer = proposal.proposer;
                                    payload = proposal.payload;                            
                                });                                
                                await delete_canister(canister_id);
                            };
                        };
                        state := #succeeded;
                    }  else if (payload.method == "add_member") {
                        switch (payload.principal_id){
                            case null { return #err("Null principal_id") };
                            case (?principal_id) {
                                state := #executing;
                                proposal_put(proposal_id, {
                                    id = proposal.id;
                                    voters_yes = proposal.voters_yes;                      
                                    state;
                                    timestamp = proposal.timestamp;
                                    proposer = proposal.proposer;
                                    payload = proposal.payload;                            
                                });                                
                                add_member(principal_id);
                            };
                        };
                        state := #succeeded;
                    } else if (payload.method == "del_member") {
                        switch (payload.principal_id){
                            case null { return #err("Null principal_id") };
                            case (?principal_id) {
                                state := #executing;
                                proposal_put(proposal_id, {
                                    id = proposal.id;
                                    voters_yes = proposal.voters_yes;                      
                                    state;
                                    timestamp = proposal.timestamp;
                                    proposer = proposal.proposer;
                                    payload = proposal.payload;                            
                                });                                
                                del_member(principal_id);
                            };
                        };
                        state := #succeeded;
                    };  
                    #ok(state)                        
                }
            };
        }
        catch (e) { #err(Error.message e) };
    };

};
