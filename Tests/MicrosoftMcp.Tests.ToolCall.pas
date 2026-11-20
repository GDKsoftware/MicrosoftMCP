unit MicrosoftMcp.Tests.ToolCall;

interface

uses
  System.JSON,
  MCPServer.Tool.Base;

type
  // Calls a tool the way the tools manager does, with a request context that carries the principal, and returns the
  // tools/call result ({"content":..., "structuredContent":..., "isError":...}). The caller frees the result.
  TToolCall = class
  private
    class function ResultOf(const Tool: IMCPTool; const Arguments: TJSONObject): TJSONObject; static;

  public
    class function Run(const Tool: IMCPTool; const Principal, ArgumentsJson: string): TJSONObject; static;

    class function IsError(const CallResult: TJSONObject): Boolean; static;
    class function Text(const CallResult: TJSONObject): string; static;
    class function Structured(const CallResult: TJSONObject): TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  System.Rtti,
  MCPServer.Types,
  MCPServer.RequestContext,
  MCPServer.Tool.Result;

{ TToolCall }

class function TToolCall.Run(const Tool: IMCPTool; const Principal, ArgumentsJson: string): TJSONObject;
begin
  const Context: IMCPRequestContext = TMCPRequestContext.Create(TMCPProtocolEra.Modern, MCP_LATEST_PROTOCOL_VERSION, 'tools/call',
                                                               TMCPRequestId.FromNumber(1), nil, nil, nil, nil, nil, nil, Principal);
  const Arguments = TJSONObject.ParseJSONValue(ArgumentsJson) as TJSONObject;
  try
    TMCPRequestContext.SetCurrent(Context);
    try
      Result := ResultOf(Tool, Arguments);
    finally
      TMCPRequestContext.SetCurrent(nil);
    end;
  finally
    Arguments.Free;
  end;
end;

class function TToolCall.ResultOf(const Tool: IMCPTool; const Arguments: TJSONObject): TJSONObject;
begin
  const Value = Tool.Execute(Arguments);

  var ToolResult: TMCPToolResult;
  if Value.IsType<TMCPToolResult> then
    ToolResult := Value.AsType<TMCPToolResult>
  else
    ToolResult := TMCPToolResult.Create.SetStructuredContent(Value.AsType<TJSONObject>);

  try
    Result := ToolResult.ToJson(TMCPProtocolEra.Modern);
  finally
    ToolResult.Free;
  end;
end;

class function TToolCall.IsError(const CallResult: TJSONObject): Boolean;
begin
  Result := False;
  CallResult.TryGetValue<Boolean>('isError', Result);
end;

class function TToolCall.Text(const CallResult: TJSONObject): string;
begin
  Result := CallResult.GetValue<string>('content[0].text');
end;

class function TToolCall.Structured(const CallResult: TJSONObject): TJSONObject;
begin
  Result := CallResult.GetValue<TJSONObject>('structuredContent');
end;

end.
