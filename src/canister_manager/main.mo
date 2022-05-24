import HashMap "mo:base/HashMap";
import List "mo:base/List";
import Trie "mo:base/Trie";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Error "mo:base/Error";
import Result "mo:base/Result";
import IC "./ic";
import Principal "mo:base/Principal";

import Cycles "mo:base/ExperimentalCycles"

import Debug "mo:base/Debug";

actor class () = self {
    
    public type Proposal = {
        id : Nat;
        voters_yes : List.List<Text>;
        state : ProposalState;
        timestamp : Int;
        proposer : Principal;
        payload : ProposalPayload;
    };

    public type ProposalPayload = {
        method : Text;
        canister_id : Text;
        // message : Blob;
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

    let wasms = HashMap.HashMap<Text,Blob>(3, Text.equal, Text.hash);
    let members: List.List<Text> = List.fromArray([
        "rwlgt-iiaaa-aaaaa-aaaaa-cai",
        "rkp4c-7iaaa-aaaaa-aaaca-cai",
        "rno2w-sqaaa-aaaaa-aaacq-cai"
    ]);
    let M = 2;

    public func uploadWasm(name : Text, wasm: Blob) : async Text {
        wasms.put(name, wasm);
        return "upload succ, name:" # name # ".";
    };

    public func getWasm(name : Text) : async ?Blob {
        wasms.get(name);
    };    

    public func create_canister(): async IC.canister_id {
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

    // DAO

    func proposal_key(t: Nat) : Trie.Key<Nat> {
        return { key = t; hash = Int.hash t };
    };  
    func proposal_get(id : Nat) : ?Proposal {
        Trie.get(proposals, proposal_key(id), Nat.equal)
    };
    func proposal_put(id : Nat, proposal : Proposal) {
        proposals := Trie.put(proposals, proposal_key(id), Nat.equal, proposal).0;
    };

    public shared({caller}) func submit_proposal(canister_id: Text, method: Text) : async (?Nat) {
        let payload: ProposalPayload = {
            method;
            canister_id;
        };
        proposal_id_seq := proposal_id_seq + 1;
        
        let proposal_id = proposal_id_seq;

        let proposal : Proposal = {
            id = proposal_id;
            timestamp = Time.now();
            proposer = caller;
            payload;
            state = #open;
            voters_yes = List.nil();
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

    public shared({caller}) func vote(proposal_id: Nat, pass: Bool) : async Result.Result<ProposalState, Text> {
        switch (proposal_get(proposal_id)) {
            case null { #err("No proposal with ID " # debug_show(proposal_id) # " exists") };
            case (?proposal) {
                var state = proposal.state;
                if (state != #open) {
                    return #err("Proposal " # debug_show(proposal_id) # " is not open for voting");
                };
            
                let call_account = Principal.toText(caller);
                var voters_yes = proposal.voters_yes;
                let is_member = List.some(members, func (p: Text): Bool {p == call_account});
                
                if (not is_member){
                    return #err("Caller:" # call_account # " is not a member")
                } else {
                    if (not List.some(voters_yes, func (p: Text): Bool {p == call_account})){
                        voters_yes := List.push(call_account, voters_yes);           
                    } else {
                        return #err("Caller:" # call_account # " has voted")
                    }
                };

                Debug.print(debug_show(voters_yes));

                if (List.size(voters_yes) >= M) {
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

    func execute_proposal(proposal_id: Nat) : async Result.Result<ProposalState, Text> {
        try {
            switch (proposal_get(proposal_id)) {
                case null { #err("No proposal with ID " # debug_show(proposal_id) # " exists") };
                case (?proposal) {
                    var state = proposal.state;
                    if (state != #accepted){
                        return #err("state err")
                    };
                    let payload = proposal.payload;
                    if (payload.method == "hold"){
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
                        // 开始对某个指定的 canister 限权
                        // await
                        state := #succeeded;
                    } else if (payload.method == "release") {
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
                        // 开始对某个指定的 canister 限权
                        // await
                        state := #succeeded;
                    };

                    proposal_put(proposal_id, {
                        id = proposal.id;
                        voters_yes = proposal.voters_yes;                              
                        state;
                        timestamp = proposal.timestamp;
                        proposer = proposal.proposer;
                        payload = proposal.payload;                            
                    });    
                    #ok(state)                        
                }
            };
        }
        catch (e) { #err(Error.message e) };
    };

};
