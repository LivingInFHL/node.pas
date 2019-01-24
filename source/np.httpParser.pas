unit np.httpParser;

interface
  uses np.Buffer, Generics.Collections;

  type
    THTTPHeader = Class(TDictionary<Utf8String,Utf8String>)
    private
       FKeys  : TList<Utf8String>;
       function GetFields(const AName: Utf8String): Utf8String;
    public
       ContentLength : int64;
       ContentType   : Utf8String;
       ContentCharset: Utf8String;
       procedure  parse(ABuf : BufferRef);
       function ToString: string; override;
       constructor Create(const ABuf: BufferRef);
       destructor Destroy; override;
       procedure addField(const key, value: Utf8String);
       procedure addSubFields(const key,value : Utf8String);
       procedure Clear;
       function HasField(const AName: Utf8String): Boolean;
       property Fields[const AName: Utf8String]: Utf8String read GetFields; default;
       property Names: TList<Utf8String> read FKeys;
    end;

  function CheckHttpAnswer(const buf: BufferRef; out protocol:UTF8string; out Code:integer; out Reason:UTF8string; out HeaderBuf:BufferRef; out ContentBuf: BufferRef) : Boolean;
  function CheckHttpRequest(const buf: BufferRef; out method:UTF8string; out uri:UTF8string; out protocol:UTF8string; out HeaderBuf:BufferRef; out ContentBuf: BufferRef) : Boolean;

  function BufCRLF : BufferRef;
  function BufCRLFCRLF : BufferRef;

implementation
  uses np.ut, sysUtils;

  const
     CONST_CRLF : array [0..3] of byte = (13,10,13,10);

  function BufCRLF : BufferRef;
  begin
     result := BufferRef.CreateWeakRef(@CONST_CRLF,2);
  end;
  function BufCRLFCRLF : BufferRef;
  begin
     result := BufferRef.CreateWeakRef(@CONST_CRLF,4);
  end;

  function _CheckHttp(const buf: BufferRef; out splitedAnswer: TArray<UTF8String>; out HeaderBuf:BufferRef; out ContentBuf: BufferRef) : Boolean;
  var
     HeaderEndPosition : integer;
     AnswerLine : UTF8String;
  begin
     HeaderEndPosition := buf.Find(BufCRLFCRLF);
     if HeaderEndPosition < 0 then
        exit(false);
     HeaderBuf := Buf.slice(0,HeaderEndPosition+2);
     ContentBuf := Buf.slice(HeaderEndPosition+4);

     HeaderEndPosition := HeaderBuf.find(BufCRLF);
     assert(HeaderEndPosition >= 0);
//     SetLength(AnswerLine, HeaderEndPosition);
//     move(HeaderBuf.ref^,AnswerLine[1], HeaderEndPosition);
     AnswerLine := HeaderBuf.slice(0,HeaderEndPosition).AsUtf8String;
     HeaderBuf.TrimL(HeaderEndPosition+2);
     splitedAnswer := WildFind('* * *',AnswerLine,3);
     result := true;
  end;


  function CheckHttpAnswer(const buf: BufferRef; out protocol:UTF8String; out Code:integer; out Reason:UTF8String; out HeaderBuf:BufferRef; out ContentBuf: BufferRef) : Boolean;
  var
    splitedAnswer: TArray<Utf8String>;
  begin
     if _CheckHttp(buf,splitedAnswer,HeaderBuf,ContentBuf) then
     begin
       protocol := splitedAnswer[0];
       Code :=  StrToIntDef( splitedAnswer[1], 0 );
       Reason := splitedAnswer[2];
       result := true;
     end
     else
       result := false;
  end;

  function CheckHttpRequest(const buf: BufferRef; out method:UTF8String; out uri:UTF8String; out protocol:UTF8String; out HeaderBuf:BufferRef; out ContentBuf: BufferRef) : Boolean;
  var
    splitedAnswer: TArray<Utf8String>;
  begin
     if _CheckHttp(buf,splitedAnswer,HeaderBuf,ContentBuf) then
     begin
       protocol := splitedAnswer[2];
       uri :=  splitedAnswer[1];
       method := splitedAnswer[0];
       result := true;
     end
     else
       result := false;
  end;

constructor THTTPHeader.Create(const ABuf: BufferRef);
begin
  inherited Create(32);
  FKeys := TList<Utf8String>.Create();
  FKeys.Capacity := 32;
  parse(ABuf);
end;

destructor THTTPHeader.Destroy;
begin
  inherited;
  FreeAndNil(FKeys);
end;

procedure THTTPHeader.addField(const key, value: Utf8String);
var
  newKey : Utf8String;
  lcount:integer;
begin
  assert(assigned( FKeys ));
  newKey := key;
  lcount := 1;
  while ContainsKey(Newkey) do
  begin
       newKey := Format('%s(%d)',[key,lcount]);
       inc(lcount);
  end;
  FKeys.Add(newKey);
  Add(newKey,StrRemoveQuote(Value));
end;

procedure THTTPHeader.Clear;
begin
  FKeys.Clear;
  inherited Clear;
  ContentLength:=0;
  ContentType :='';
  ContentCharset := '';
end;

function THTTPHeader.GetFields(const AName: Utf8String): Utf8String;
begin
  if not TryGetValue(AName,result) then
     Result := '';
end;

function THTTPHeader.HasField(const AName: Utf8String): Boolean;
begin
  Result := ContainsKey(AName);
end;

{ THTTPHeader }

procedure THTTPHeader.parse(ABuf: BufferRef);
var
  i : integer;
  tmp,line : BUfferREf;
  key,value: BufferRef;
  s : Utf8String;
begin
  tmp := ABuf;
  while tmp.length > 0 do
  begin
    i := tmp.Find( bufCRLF );
    if i < 0 then
    begin
       line := tmp;
       tmp := Buffer.Null;
    end
    else
    begin
      line := tmp.slice(0,i);
      tmp.TrimL(i+2);
    end;

    for i := 0 to line.length-1 do
    begin
       if line.ref[i] <> ord(':') then
         continue;
       key := line.slice(0,i);
       value := line.slice(i+1);
       AddSubFields( trim( LowerCase(  key.AsUtf8String ) ), trim(value.AsUtf8String) );
       break;
    end;
  end;
  TryGetValue('content-type',ContentType);
  TryGetValue('content-type.charset', ContentCharset);
  if TryGetValue('content-length',s) and
    TryStrToInt64(s,ContentLength) then;
end;

procedure THttpHeader.addSubFields(const key,value : Utf8string);
var
  values, kv: TArray<Utf8String>;
  k : integer;
begin
       if (key = 'date') or (Key = 'expires') or (Key='server') or (key='cashe-control')
          or (Key = 'user-agent') then
       begin
          addField(Key,Value);
       end
       else
       begin
         SplitString( Value,values, [';',',',' ']);
         if length(values) > 0 then
         begin
           if SplitString( values[0], kv,['='] ) = 1 then
           begin
              addField(key,trim(kv[0]));
           end;
             for k := 0 to length(values)-1 do
             begin
                SplitString( values[k], kv,['='] );
                if (k=0) and (length(kv)=1) then
                   continue;
                SetLength(kv,2);
                kv[0] := LowerCase(trim(kv[0]));
                addField(key+'.'+kv[0],trim(kv[1]));
             end;
         end;
       end;
end;


function THTTPHeader.ToString: string;
var
  k : string;
  sb : TStringBuilder;
begin
  if (Count = 0) then
      exit('(empty)')
  else
  begin
    sb := TStringBuilder.Create;
    try
      for k in FKeys do
      begin
        sb.Append(k).Append(' = ').Append(Fields[k]).AppendLine;
      end;
      result := sb.toString;
    finally
      sb.Free;
    end;
  end;
end;

end.
