import Principal "mo:base/Principal";

actor {
    public func greet(name : Text) : async Text {
        return "Hello, " # name # "!";
    };
};
