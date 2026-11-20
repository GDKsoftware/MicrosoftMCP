unit MicrosoftMcp.Confirm.Interfaces;

interface

type
  // Two-step confirmation of tools that change or send something: the first call gets a token, the second call with
  // the same arguments redeems it. A token works once, for one user, one tool and one argument hash.
  IConfirmations = interface
    ['{6A1F3C58-2D94-4B7E-8C05-E9B2D47A1F36}']
    // A new token, valid for ten minutes.
    function Issue(const UserId, ToolName, ArgumentsHash, Summary: string): string;

    // True once for a valid token of this user, tool and argument hash; the token is then used up.
    function TryRedeem(const UserId, ToolName, ArgumentsHash, Token: string): Boolean;

    // The number of expired tokens removed.
    function DeleteExpired: Integer;
  end;

implementation

end.
