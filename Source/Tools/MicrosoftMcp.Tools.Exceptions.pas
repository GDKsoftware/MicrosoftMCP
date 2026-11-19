unit MicrosoftMcp.Tools.Exceptions;

interface

uses
  System.SysUtils;

type
  // A tool failure whose message is written for Claude; the tool base returns it unchanged as a tool error.
  EToolError = class(Exception);
  EToolNoUser = class(EToolError);
  EToolArgumentError = class(EToolError);

implementation

end.
