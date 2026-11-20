unit MicrosoftMcp.Server.Exceptions;

interface

uses
  System.SysUtils;

type
  // The message names the setting, never its value: values can be secrets or connection strings.
  EServerConfiguration = class(Exception);

implementation

end.
