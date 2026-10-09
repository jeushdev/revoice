import Foundation

/// GBNF grammars (llama.cpp's constrained-output format) so a small model can only emit valid JSON.
/// Grammar guarantees the SHAPE only; Dart still validates content and evidence (PRD section 6).
enum ReviseGrammars {
    /// Shared building blocks. Output is one compact line, formatted exactly like the worked
    /// example in `crmSystem`. (Allowing optional whitespace let the model slip into "[\n ]" and
    /// return empty lists instead of filling them.)
    private static let common = #"""
    string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\""
    nullable-string ::= string | "null"
    string-array ::= "[" (string (", " string)*)? "]"
    """#

    /// CRM card, PRD section 8: exactly the nine keys the Dart prompt asks for.
    /// `source_segments` maps a field path ("role", "topics[0]", ...) to supporting segment IDs.
    /// (GBNF rules end at a newline unless inside parentheses, hence the wrapped `root`.)
    static let crm = #"""
    root ::= (
      "{" "\"name\": " nullable-string ", "
      "\"role\": " nullable-string ", "
      "\"organization\": " nullable-string ", "
      "\"contact_mentioned\": " nullable-string ", "
      "\"topics\": " string-array ", "
      "\"commitments\": " commitments ", "
      "\"follow_up\": " nullable-string ", "
      "\"notes\": " nullable-string ", "
      "\"source_segments\": " sources "}"
    )
    commitments ::= "[" (commitment (", " commitment)*)? "]"
    commitment ::= "{" "\"what\": " string ", " "\"due\": " nullable-string "}"
    sources ::= "{" source (", " source)* "}"
    source ::= string ": " string-array

    """# + common

    /// Same card, but `source_segments` is always `{}`: the model only writes values, and
    /// `CrmEvidence` fills the citations afterwards (fewer tokens, more accurate citations).
    static let crmValuesOnly = crm
        .replacingOccurrences(of: #""\"source_segments\": " sources "}""#, with: #""\"source_segments\": {}" "}""#)

    /// Any valid JSON value, for the generic `generate` method with `jsonGrammar: true`.
    static let anyJson = #"""
    root ::= object
    value ::= object | array | string | number | ("true" | "false" | "null") ws
    object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws
    array ::= "[" ws (value ("," ws value)*)? "]" ws
    string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\"" ws
    number ::= ("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws
    ws ::= | " " | "\n" [ \t]{0,20}
    """#

    /// System prompt for `generateCrm`. A small model follows a worked example much better than
    /// rules alone; without it the 1.5B model leaves `source_segments` empty, and the Dart side
    /// drops every field that has no evidence. The example content is deliberately unrelated to
    /// any real conversation.
    static let crmSystem = #"""
    You are a careful information extractor. Reply with one JSON object and nothing else.
    Fill a field only with facts the person stated. Every filled field and every list item must be listed in source_segments with the [segment ids] of the lines that state it. Copy emails, phone numbers and dates exactly as spoken. contact_mentioned is ONLY an email address or phone number the person said; otherwise null. If a fact is not stated, use null (or []).

    Example transcript:
    [s-0002] I'm Ben, I run operations at Delta Foods.
    [s-0004] I'll call the supplier on Tuesday. Reach me at ben@delta.example.

    Example reply:
    {"name": "Ben", "role": "operations lead", "organization": "Delta Foods", "contact_mentioned": "ben@delta.example", "topics": ["supplier"], "commitments": [{"what": "call the supplier", "due": "Tuesday"}], "follow_up": null, "notes": null, "source_segments": {"role": ["s-0002"], "organization": ["s-0002"], "contact_mentioned": ["s-0004"], "topics[0]": ["s-0004"], "commitments[0].what": ["s-0004"], "commitments[0].due": ["s-0004"]}}
    """#

    /// System prompt matching `crmValuesOnly`: same worked-example style, no citation rules.
    static let crmValuesOnlySystem = #"""
    You are a careful information extractor. Reply with one JSON object and nothing else.
    Fill a field only with facts the person stated. Copy emails, phone numbers and dates exactly as spoken. contact_mentioned is ONLY an email address or phone number the person said; otherwise null. If a fact is not stated, use null (or []). Always write "source_segments": {} exactly.

    Example transcript:
    [s-0002] I'm Ben, I run operations at Delta Foods.
    [s-0004] I'll call the supplier on Tuesday. Reach me at ben@delta.example.

    Example reply:
    {"name": "Ben", "role": "operations lead", "organization": "Delta Foods", "contact_mentioned": "ben@delta.example", "topics": ["supplier"], "commitments": [{"what": "call the supplier", "due": "Tuesday"}], "follow_up": null, "notes": null, "source_segments": {}}
    """#
}
