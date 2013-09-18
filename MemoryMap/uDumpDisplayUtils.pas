unit uDumpDisplayUtils;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.DateUtils,
  System.StrUtils;

  function DumpMemory(Process: THandle; Address: Pointer): string;
  function DumpPEB32(Process: THandle; Address: Pointer): string;
  function DumpPEB64(Process: THandle; Address: Pointer): string;
  function DumpPEHeader(Process: THandle; Address: Pointer): string;
  function DumpThread64(Process: THandle; Address: Pointer): string;
  function DumpThread32(Process: THandle; Address: Pointer): string;
  function DumpKUserSharedData(Process: THandle; Address: Pointer): string;

implementation

uses
  uUtils;

const
  MemoryDumpHeader =
    '-------------------------------------------- Memory dump -------------------------------------------------';
  PEBHeader =
    '------------------------------------- Process Environment Block ------------------------------------------';
  TEB_Header =
    '-------------------------------------- Thread Environment Block ------------------------------------------';
  PEHeader =
    '------------------------------------------ IMAGE_DOS_HEADER ----------------------------------------------';
  NT_HEADERS =
    '------------------------------------------ IMAGE_NT_HEADERS ----------------------------------------------';
  FILE_HEADER =
    '------------------------------------------ IMAGE_FILE_HEADER ---------------------------------------------';
  OPTIONAL_HEADER32 =
    '--------------------------------------- IMAGE_OPTIONAL_HEADER32 ------------------------------------------';
  OPTIONAL_HEADER64 =
    '--------------------------------------- IMAGE_OPTIONAL_HEADER64 ------------------------------------------';
  DATA_DIRECTORY =
    '----------------------------------------- IMAGE_DATA_DIRECTORY -------------------------------------------';
  SECTION_HEADERS =
    '---------------------------------------- IMAGE_SECTION_HEADERS -------------------------------------------';
  EmptyHeader =
    '----------------------------------------------------------------------------------------------------------';
  KUSER =
    '------------------------------------------ KUSER_SHARED_DATA ---------------------------------------------';
type
  TDataType = (dtByte, dtWord, dtDword,
    dtInt64, dtString, dtAnsiString, dtBuff, dtUnicodeString32,
    dtUnicodeString64);

function ByteToHexStr(Base: NativeUInt; Data: Pointer;
  Len: Integer; const Comment: string = ''): string;
var
  I, PartOctets: Integer;
  Octets: NativeUInt;
  DumpData: string;
  CommentAdded: Boolean;
begin
  if Len = 0 then Exit;
  I := 0;
  Octets := Base;
  PartOctets := 0;
  Result := '';
  CommentAdded := False;
  while I < Len do
  begin
    case PartOctets of
      0: Result := Result + UInt64ToStr(Octets) + ' ';
      9: Result := Result + '| ';
      18:
      begin
        Inc(Octets, 16);
        PartOctets := -1;
        if Comment <> '' then
        begin
          if CommentAdded then
            Result := Result + sLineBreak
          else
          begin
            Result := Result + '    ' + Comment + sLineBreak;
            CommentAdded := True;
          end;
        end
        else
          Result := Result + '    ' + DumpData + sLineBreak;
        DumpData := '';
      end;
    else
      begin
        Result := Result + Format('%s ', [IntToHex(TByteArray(Data^)[I], 2)]);
        if TByteArray(Data^)[I] in [$19..$FF] then
          DumpData := DumpData + Char(AnsiChar(TByteArray(Data^)[I]))
        else
          DumpData := DumpData + '.';
        Inc(I);
      end;
    end;
    Inc(PartOctets);
  end;
  if PartOctets <> 0 then
  begin
    PartOctets := (16 - Length(DumpData)) * 3;
    if PartOctets >= 24 then Inc(PartOctets, 2);
    Inc(PartOctets, 4);
    if Comment <> '' then
    begin
      if not CommentAdded then
        Result := Result + StringOfChar(' ', PartOctets) + Comment;
    end
    else
      Result := Result + StringOfChar(' ', PartOctets) + DumpData;
  end;
end;

procedure AddString(var OutValue: string; const NewString, SubComment: string); overload;
var
  Line: string;
  sLineBreakOffset, SubCommentOffset: Integer;
begin
  if SubComment = '' then
    OutValue := OutValue + NewString + sLineBreak
  else
  begin
    sLineBreakOffset := Pos(#13, NewString);
    if sLineBreakOffset = 0 then
    begin
      SubCommentOffset := 106 - Length(NewString);
      Line := NewString + StringOfChar(' ', SubCommentOffset) + ' // ' + SubComment;
    end
    else
    begin
      SubCommentOffset := 107 - sLineBreakOffset;
      Line := StuffString(NewString, sLineBreakOffset, 0,
        StringOfChar(' ', SubCommentOffset) + ' // ' + SubComment);
    end;
    OutValue := OutValue + Line + sLineBreak;
  end;
end;

procedure AddString(var OutValue: string; const NewString: string); overload;
begin
  AddString(OutValue, NewString, '');
end;

var
  CurerntAddr: Pointer;

procedure AddString(var OutValue: string; const Comment: string; Address: Pointer;
  DataType: TDataType; Size: Integer; var Cursor: NativeUInt;
  const SubComment: string = ''); overload;
var
  UString: string;
  AString: AnsiString;
begin
  UString := '';
  case DataType of
    dtByte: UString := IntToHex(PByte(Address)^, 1);
    dtWord: UString := IntToHex(PWord(Address)^, 1);
    dtDword: UString := IntToHex(PDWORD(Address)^, 1);
    dtInt64: UString := IntToHex(PInt64(Address)^, 1);
    dtString:
    begin
      SetLength(UString, Size div 2);
      Move(PByte(Address)^, UString[1], Size);
      UString := '"' + PChar(UString) + '"';
    end;
    dtAnsiString:
    begin
      SetLength(AString, Size);
      Move(PByte(Address)^, AString[1], Size);
      UString := '"' + string(PAnsiChar(AString)) + '"';
    end;
  end;
  if UString = '' then
    AddString(OutValue, ByteToHexStr(NativeUInt(CurerntAddr) + Cursor,
      Address, Size, Comment), SubComment)
  else
    AddString(OutValue, ByteToHexStr(NativeUInt(CurerntAddr) + Cursor,
      Address, Size, Comment + ' = ' + UString), SubComment);
  Inc(Cursor, Size);
end;

procedure AddString(var OutValue: string; const Comment: string; Address: Pointer;
  DataType: TDataType; var Cursor: NativeUInt;
  const SubComment: string = ''); overload;
begin
  case DataType of
    dtByte: AddString(OutValue, Comment, Address, DataType, 1, Cursor, SubComment);
    dtWord: AddString(OutValue, Comment, Address, DataType, 2, Cursor, SubComment);
    dtDword: AddString(OutValue, Comment, Address, DataType, 4, Cursor, SubComment);
    dtInt64: AddString(OutValue, Comment, Address, DataType, 8, Cursor, SubComment);
    dtUnicodeString32: AddString(OutValue, Comment, Address, DataType, 8, Cursor, SubComment);
    dtUnicodeString64: AddString(OutValue, Comment, Address, DataType, 16, Cursor, SubComment);
  end;
end;

function DumpMemory(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, RegionSize: NativeUInt;
begin
  Result := '';
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address), @Buff[0], Size));
end;

function PebBitFieldToStr(Value: Byte): string;

  procedure AddToResult(const Value: string);
  begin
    if Result = '' then
      Result := Value
    else
      Result := Result + ', ' + Value;
  end;

begin
  if Value and 1 <> 0 then AddToResult('ImageUsesLargePages');
  if Value and 2 <> 0 then AddToResult('IsProtectedProcess');
  if Value and 4 <> 0 then AddToResult('IsLegacyProcess');
  if Value and 8 <> 0 then AddToResult('IsImageDynamicallyRelocated');
  if Value and 16 <> 0 then AddToResult('SkipPatchingUser32Forwarders');
  if Value and 32 <> 0 then AddToResult('IsPackagedProcess');
  if Value and 64 <> 0 then AddToResult('IsAppContainer');
  Result := 'BitField [' + Result + ']';
end;

function PebTracingFlagsToStr(Value: Byte): string;

  procedure AddToResult(const Value: string);
  begin
    if Result = '' then
      Result := Value
    else
      Result := Result + ', ' + Value;
  end;

begin
  if Value and 1 <> 0 then AddToResult('HeapTracingEnabled');
  if Value and 2 <> 0 then AddToResult('CritSecTracingEnabled');
  if Value and 4 <> 0 then AddToResult('LibLoaderTracingEnabled');
  Result := 'TracingFlags [' + Result + ']';
end;

function ExtractUnicodeString32(Process: THandle; Address: Pointer): string;
var
  Size, Dummy: NativeUInt;
begin
  Result := '';
  Size := PWord(Address)^;
  if Size = 0 then Exit;
  SetLength(Result, Size div 2);
  Address := PByte(Address) + 4;
  Address := Pointer(PDWORD(Address)^);
  ReadProcessData(Process, Address, @Result[1],
    Size, Dummy, rcReadAllwais);
  Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "' + PChar(Result) + '"';
end;

function ExtractUnicodeString64(Process: THandle; Address: Pointer): string;
var
  Size, Dummy: NativeUInt;
begin
  Result := '';
  Size := PDWORD(Address)^;
  if Size = 0 then Exit;
  SetLength(Result, Size div 2);
  Address := PByte(Address) + 8;
  Address := Pointer(Address^);
  ReadProcessData(Process, Address, @Result[1],
    Size, Dummy, rcReadAllwais);
  Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "' + PChar(Result) + '"';
end;

function ExtractPPVoidData32(Process: THandle; Address: Pointer): string;
var
  Data: Pointer;
  Size, Dummy: NativeUInt;
begin
  Size := 4;
  Address := Pointer(PDWORD(Address)^);
  if Address = nil then Exit('[NULL] "NULL"');
  if not ReadProcessData(Process, Address, @Data,
    Size, Dummy, rcReadAllwais) then
    Exit('[' + IntToHex(ULONG_PTR(Address), 1) + ']');
  if Data = nil then
    Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "NULL"'
  else
    Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "' +
      IntToHex(ULONG_PTR(Data), 1) + '"';
end;

function ExtractPPVoidData64(Process: THandle; Address: Pointer): string;
var
  Data: Pointer;
  Size, Dummy: NativeUInt;
begin
  Size := 8;
  Address := Pointer(Address^);
  if Address = nil then Exit('[NULL] "NULL"');
  if not ReadProcessData(Process, Address, @Data,
    Size, Dummy, rcReadAllwais) then
    Exit('[' + IntToHex(ULONG_PTR(Address), 1) + ']');
  if Data = nil then
    Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "NULL"'
  else
    Result := '[' + IntToHex(ULONG_PTR(Address), 1) + '] "' +
      IntToHex(ULONG_PTR(Data), 1) + '"';
end;

function DumpPEB32(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, Dummy, Cursor: NativeUInt;
begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, Dummy, rcReadAllwais) then Exit;
  Cursor := 0;
  AddString(Result, PEBHeader);
  AddString(Result, 'InheritedAddressSpace', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'ReadImageFileExecOptions', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'BeingDebugged', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, PebBitFieldTostr(Buff[Cursor]), @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'Mutant', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ImageBaseAddress', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'LoaderData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessParameters', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SubSystemData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessHeap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'FastPebLock', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AtlThunkSListPtr', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'IFEOKey', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'EnvironmentUpdateCount', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'UserSharedInfoPtr', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SystemReserved', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AtlThunkSListPtr32', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ApiSetMap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsExpansionCounter', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsBitmap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsBitmapBits[0]', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsBitmapBits[1]', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ReadOnlySharedMemoryBase', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'HotpatchInformation', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ReadOnlyStaticServerData = ' + ExtractPPVoidData32(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'AnsiCodePageData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'OemCodePageData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'UnicodeCaseTableData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'KeNumberOfProcessors', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtGlobalFlag', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'CriticalSectionTimeout', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HeapSegmentReserve', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'HeapSegmentCommit', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'HeapDeCommitTotalFreeThreshold', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'HeapDeCommitFreeBlockThreshold', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NumberOfHeaps', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MaximumNumberOfHeaps', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessHeaps = ' + ExtractPPVoidData32(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'GdiSharedHandleTable', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessStarterHelper', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'GdiDCAttributeList', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'LoaderLock', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtMajorVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtMinorVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtBuildNumber', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'NtCSDVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'PlatformId', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Subsystem', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MajorSubsystemVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MinorSubsystemVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AffinityMask', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'GdiHandleBuffer', @Buff[Cursor], dtBuff, 136, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'PostProcessInitRoutine', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsExpansionBitmap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'TlsExpansionBitmapBits', @Buff[Cursor], dtBuff, 128, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'SessionId', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AppCompatFlags', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'AppCompatFlagsUser', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'pShimData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AppCompatInfo', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'CSDVersion = ' + ExtractUnicodeString32(Process, @Buff[Cursor]),
    @Buff[Cursor], dtUnicodeString32, Cursor);
  AddString(Result, 'ActivationContextData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessAssemblyStorageMap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SystemDefaultActivationContextData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SystemAssemblyStorageMap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MinimumStackCommit', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'FlsCallback = ' + ExtractPPVoidData32(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'FlsListHead.FLink', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'FlsListHead.BLink', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'FlsBitmap', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'FlsBitmapBits', @Buff[Cursor], dtBuff, 256, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'FlsHighIndex', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'WerRegistrationData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'WerShipAssertPtr', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'pContextData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'pImageHeaderHash', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, PebTracingFlagsToStr(Buff[Cursor]), @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'CsrServerReadOnlySharedMemoryBase', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;

function DumpPEB64(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, RegionSize, Cursor: NativeUInt;
begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  Cursor := 0;
  AddString(Result, PEBHeader);
  AddString(Result, 'InheritedAddressSpace', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'ReadImageFileExecOptions', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'BeingDebugged', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, PebBitFieldTostr(Buff[Cursor]), @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'Mutant', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ImageBaseAddress', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'LoaderData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ProcessParameters', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SubSystemData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ProcessHeap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'FastPebLock', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'AtlThunkSListPtr', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'IFEOKey', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'EnvironmentUpdateCount', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'UserSharedInfoPtr', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SystemReserved', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AtlThunkSListPtr32', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ApiSetMap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'TlsExpansionCounter', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'TlsBitmap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'TlsBitmapBits[0]', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TlsBitmapBits[1]', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ReadOnlySharedMemoryBase', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HotpatchInformation', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ReadOnlyStaticServerData = ' + ExtractPPVoidData64(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 8, Cursor);
  AddString(Result, 'AnsiCodePageData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'OemCodePageData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'UnicodeCaseTableData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'KeNumberOfProcessors', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtGlobalFlag', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'CriticalSectionTimeout', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HeapSegmentReserve', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HeapSegmentCommit', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HeapDeCommitTotalFreeThreshold', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'HeapDeCommitFreeBlockThreshold', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'NumberOfHeaps', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MaximumNumberOfHeaps', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ProcessHeaps = ' + ExtractPPVoidData64(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 8, Cursor);
  AddString(Result, 'GdiSharedHandleTable', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ProcessStarterHelper', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'GdiDCAttributeList', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'LoaderLock', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'NtMajorVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtMinorVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtBuildNumber', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'NtCSDVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'PlatformId', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Subsystem', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MajorSubsystemVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MinorSubsystemVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'AffinityMask', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'GdiHandleBuffer', @Buff[Cursor], dtBuff, 240, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'PostProcessInitRoutine', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'TlsExpansionBitmap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'TlsExpansionBitmapBits', @Buff[Cursor], dtBuff, 128, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'SessionId', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'AppCompatFlags', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'AppCompatFlagsUser', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'pShimData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'AppCompatInfo', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'CSDVersion = ' + ExtractUnicodeString64(Process, @Buff[Cursor]),
    @Buff[Cursor], dtUnicodeString64, Cursor);
  AddString(Result, 'ActivationContextData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'ProcessAssemblyStorageMap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SystemDefaultActivationContextData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SystemAssemblyStorageMap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'MinimumStackCommit', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'FlsCallback = ' + ExtractPPVoidData64(Process, @Buff[Cursor]),
    @Buff[Cursor], dtBuff, 8, Cursor);
  AddString(Result, 'FlsListHead.FLink', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'FlsListHead.BLink', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'FlsBitmap', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'FlsBitmapBits', @Buff[Cursor], dtBuff, 256, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'FlsHighIndex', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'WerRegistrationData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'WerShipAssertPtr', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'pContextData', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'pImageHeaderHash', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, PebTracingFlagsToStr(Buff[Cursor]), @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Spare', @Buff[Cursor], dtBuff, 4, Cursor);
  AddString(Result, 'CsrServerReadOnlySharedMemoryBase', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;

function FileHeaderMachineToStr(Value: Word): string;
begin
  case Value of
    IMAGE_FILE_MACHINE_I386: Result := 'IMAGE_FILE_MACHINE_I386';
    IMAGE_FILE_MACHINE_R3000: Result := 'IMAGE_FILE_MACHINE_R3000';
    IMAGE_FILE_MACHINE_R4000: Result := 'IMAGE_FILE_MACHINE_R4000';
    IMAGE_FILE_MACHINE_R10000: Result := 'IMAGE_FILE_MACHINE_R10000';
    IMAGE_FILE_MACHINE_ALPHA: Result := 'IMAGE_FILE_MACHINE_ALPHA';
    IMAGE_FILE_MACHINE_POWERPC: Result := 'IMAGE_FILE_MACHINE_POWERPC';
    IMAGE_FILE_MACHINE_IA64: Result := 'IMAGE_FILE_MACHINE_IA64';
    IMAGE_FILE_MACHINE_ALPHA64: Result := 'IMAGE_FILE_MACHINE_ALPHA64';
    IMAGE_FILE_MACHINE_AMD64: Result := 'IMAGE_FILE_MACHINE_AMD64';
  else
    Result := 'IMAGE_FILE_MACHINE_UNKNOWN';
  end;
end;

function FileHeaderTimeStampToStr(Value: DWORD): string;
var
  D: TDateTime;
begin
  D := EncodeDateTime(1970, 1, 1, 0, 0, 0, 0);
  D := IncSecond(D, Value);
  Result := DateTimeToStr(D);
end;

function FileHeaderCharacteristicsToStr(Value: Word): string;

  procedure AddResult(const Value: string);
  begin
    if Result = '' then
      Result := Value
    else
      Result := Result + '|' + Value;
  end;

begin
  Result := '';
  if Value and IMAGE_FILE_RELOCS_STRIPPED <> 0 then
    AddResult('RELOCS_STRIPPED');
  if Value and IMAGE_FILE_EXECUTABLE_IMAGE <> 0 then
    AddResult('EXECUTABLE_IMAGE');
  if Value and IMAGE_FILE_LINE_NUMS_STRIPPED <> 0 then
    AddResult('LINE_NUMS_STRIPPED');
  if Value and IMAGE_FILE_LOCAL_SYMS_STRIPPED <> 0 then
    AddResult('LOCAL_SYMS_STRIPPED');
  if Value and IMAGE_FILE_AGGRESIVE_WS_TRIM <> 0 then
    AddResult('AGGRESIVE_WS_TRIM');
  if Value and IMAGE_FILE_LARGE_ADDRESS_AWARE <> 0 then
    AddResult('LARGE_ADDRESS_AWARE');
  if Value and IMAGE_FILE_BYTES_REVERSED_LO <> 0 then
    AddResult('BYTES_REVERSED_LO');
  if Value and IMAGE_FILE_32BIT_MACHINE <> 0 then
    AddResult('32BIT_MACHINE');
  if Value and IMAGE_FILE_DEBUG_STRIPPED <> 0 then
    AddResult('DEBUG_STRIPPED');
  if Value and IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP <> 0 then
    AddResult('REMOVABLE_RUN_FROM_SWAP');
  if Value and IMAGE_FILE_NET_RUN_FROM_SWAP <> 0 then
    AddResult('NET_RUN_FROM_SWAP');
  if Value and IMAGE_FILE_SYSTEM <> 0 then
    AddResult('SYSTEM');
  if Value and IMAGE_FILE_DLL <> 0 then
    AddResult('DLL');
  if Value and IMAGE_FILE_UP_SYSTEM_ONLY <> 0 then
    AddResult('UP_SYSTEM_ONLY');
  if Value and IMAGE_FILE_BYTES_REVERSED_HI <> 0 then
    AddResult('BYTES_REVERSED_HI');
end;

function OptionalHeaderMagicToStr(Value: Word): string;
begin
  case Value of
    IMAGE_NT_OPTIONAL_HDR32_MAGIC: Result := 'IMAGE_NT_OPTIONAL_HDR32_MAGIC';
    IMAGE_NT_OPTIONAL_HDR64_MAGIC: Result := 'IMAGE_NT_OPTIONAL_HDR64_MAGIC';
    IMAGE_ROM_OPTIONAL_HDR_MAGIC: Result := 'IMAGE_ROM_OPTIONAL_HDR_MAGIC';
  else
    Result := '';
  end;
end;

function OptionalHeaderSubsystemToStr(Value: Word): string;
const
  SubsystemsString: array [0..8] of string = (
    'IMAGE_SUBSYSTEM_UNKNOWN',
    'IMAGE_SUBSYSTEM_NATIVE',
    'IMAGE_SUBSYSTEM_WINDOWS_GUI',
    'IMAGE_SUBSYSTEM_WINDOWS_CUI',
    '',
    'IMAGE_SUBSYSTEM_OS2_CUI',
    '',
    'IMAGE_SUBSYSTEM_POSIX_CUI',
    'IMAGE_SUBSYSTEM_RESERVED8');
begin
  if Value in [0..3, 5, 7, 8] then
    Result := SubsystemsString[Value]
  else
    Result := SubsystemsString[0];
end;

function SectionCharacteristicsToStr(Value: DWORD): string;

  procedure AddResult(const Value: string);
  begin
    if Result = '' then
      Result := Value
    else
      Result := Result + '|' + Value;
  end;

begin
  Result := '';
  if Value and IMAGE_SCN_CNT_CODE <> 0 then
    AddResult('CNT_CODE');
  if Value and IMAGE_SCN_CNT_INITIALIZED_DATA <> 0 then
    AddResult('CNT_INITIALIZED_DATA');
  if Value and IMAGE_SCN_CNT_UNINITIALIZED_DATA <> 0 then
    AddResult('CNT_UNINITIALIZED_DATA');
  if Value and IMAGE_SCN_LNK_INFO <> 0 then
    AddResult('LNK_INFO');
  if Value and IMAGE_SCN_LNK_REMOVE <> 0 then
    AddResult('LNK_REMOVE');
  if Value and IMAGE_SCN_LNK_COMDAT <> 0 then
    AddResult('LNK_COMDAT');
  if Value and IMAGE_SCN_MEM_FARDATA <> 0 then
    AddResult('MEM_FARDATA');
  if Value and IMAGE_SCN_MEM_PURGEABLE <> 0 then
    AddResult('MEM_PURGEABLE');
  if Value and IMAGE_SCN_MEM_16BIT <> 0 then
    AddResult('MEM_16BIT');
  if Value and IMAGE_SCN_MEM_LOCKED <> 0 then
    AddResult('MEM_LOCKED');
  if Value and IMAGE_SCN_MEM_PRELOAD <> 0 then
    AddResult('MEM_PRELOAD');
  if Value and IMAGE_SCN_ALIGN_1BYTES <> 0 then
    AddResult('ALIGN_1BYTES');
  if Value and IMAGE_SCN_ALIGN_2BYTES <> 0 then
    AddResult('ALIGN_2BYTES');
  if Value and IMAGE_SCN_ALIGN_4BYTES <> 0 then
    AddResult('ALIGN_4BYTES');
  if Value and IMAGE_SCN_ALIGN_8BYTES <> 0 then
    AddResult('ALIGN_8BYTES');
  if Value and IMAGE_SCN_ALIGN_16BYTES <> 0 then
    AddResult('ALIGN_16BYTES');
  if Value and IMAGE_SCN_ALIGN_32BYTES <> 0 then
    AddResult('ALIGN_32BYTES');
  if Value and IMAGE_SCN_ALIGN_64BYTES <> 0 then
    AddResult('ALIGN_64BYTES');
  if Value and IMAGE_SCN_LNK_NRELOC_OVFL <> 0 then
    AddResult('LNK_NRELOC_OVFL');
  if Value and IMAGE_SCN_MEM_DISCARDABLE <> 0 then
    AddResult('MEM_DISCARDABLE');
  if Value and IMAGE_SCN_MEM_NOT_CACHED <> 0 then
    AddResult('MEM_NOT_CACHED');
  if Value and IMAGE_SCN_MEM_NOT_PAGED <> 0 then
    AddResult('MEM_NOT_PAGED');
  if Value and IMAGE_SCN_MEM_SHARED <> 0 then
    AddResult('MEM_SHARED');
  if Value and IMAGE_SCN_MEM_EXECUTE <> 0 then
    AddResult('MEM_EXECUTE');
  if Value and IMAGE_SCN_MEM_READ <> 0 then
    AddResult('MEM_READ');
  if Value and IMAGE_SCN_MEM_WRITE <> 0 then
    AddResult('MEM_WRITE');
end;

function DumpPEHeader(Process: THandle; Address: Pointer): string;
const
  DataDirectoriesName: array [0..IMAGE_NUMBEROF_DIRECTORY_ENTRIES - 1] of string =
    ('Export', 'Import', 'Resource', 'Exception', 'Security', 'BaseReloc',
    'Debug', 'Copyright', 'GlobalPTR', 'TLS', 'Load config', 'Bound import',
    'Iat', 'Delay import', 'COM', 'Reserved');
var
  Buff: array of Byte;
  Size, RegionSize, Cursor: NativeUInt;
  ValueBuff: DWORD;
  Optional32: Boolean;
  I: Integer;
  NumberOfSections: Word;

  procedure DumpDataDirectory(Index: Integer);
  begin
    AddString(Result, DataDirectoriesName[Index] +
      ' Directory Address', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, DataDirectoriesName[Index] +
      ' Directory Size', @Buff[Cursor], dtDword, Cursor);
  end;

  procedure DumpSection;
  begin
    AddString(Result, 'Name', @Buff[Cursor], dtAnsiString, IMAGE_SIZEOF_SHORT_NAME, Cursor);
    AddString(Result, 'VirtualSize', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'VirtualAddress', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'SizeOfRawData', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'PointerToRawData', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'PointerToRelocations', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'PointerToLinenumbers', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'NumberOfRelocations', @Buff[Cursor], dtWord, Cursor);
    AddString(Result, 'NumberOfLinenumbers', @Buff[Cursor], dtWord, Cursor);
    ValueBuff := PDWORD(@Buff[Cursor])^;
    AddString(Result, 'Characteristics', @Buff[Cursor], dtDword, Cursor,
      SectionCharacteristicsToStr(ValueBuff));
  end;

begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  Cursor := 0;

  // IMAGE_DOS_HEADER
  AddString(Result, PEHeader);
  AddString(Result, 'e_magic', @Buff[Cursor], dtAnsiString, 2, Cursor, 'Magic number');
  AddString(Result, 'e_cblp', @Buff[Cursor], dtWord, Cursor, 'Bytes on last page of file');
  AddString(Result, 'e_cp', @Buff[Cursor], dtWord, Cursor, 'Pages in file');
  AddString(Result, 'e_crlc', @Buff[Cursor], dtWord, Cursor, 'Relocations');
  AddString(Result, 'e_cparhdr', @Buff[Cursor], dtWord, Cursor, 'Size of header in paragraphs');
  AddString(Result, 'e_minalloc', @Buff[Cursor], dtWord, Cursor, 'Minimum extra paragraphs needed');
  AddString(Result, 'e_maxalloc', @Buff[Cursor], dtWord, Cursor, 'Maximum extra paragraphs needed');
  AddString(Result, 'e_ss', @Buff[Cursor], dtWord, Cursor, 'Initial (relative) SS value');
  AddString(Result, 'e_sp', @Buff[Cursor], dtWord, Cursor, 'Initial SP value');
  AddString(Result, 'e_csum', @Buff[Cursor], dtWord, Cursor, 'Checksum');
  AddString(Result, 'e_ip', @Buff[Cursor], dtWord, Cursor, 'Initial IP value');
  AddString(Result, 'e_cs', @Buff[Cursor], dtWord, Cursor, 'Initial (relative) CS value');
  AddString(Result, 'e_lfarlc', @Buff[Cursor], dtWord, Cursor, 'File address of relocation table');
  AddString(Result, 'e_ovno', @Buff[Cursor], dtWord, Cursor, 'Overlay number');
  AddString(Result, 'e_res', @Buff[Cursor], dtBuff, 8, Cursor, 'Reserved words');
  AddString(Result, 'e_oemid', @Buff[Cursor], dtWord, Cursor, 'OEM identifier (for e_oeminfo)');
  AddString(Result, 'e_oeminfo', @Buff[Cursor], dtWord, Cursor, 'OEM information; e_oemid specific');
  AddString(Result, 'e_res2', @Buff[Cursor], dtBuff, 20, Cursor, 'Reserved words');
  ValueBuff := PLongInt(@Buff[Cursor])^;
  AddString(Result, '_lfanew', @Buff[Cursor], dtDword, Cursor, 'File address of new exe header');

  AddString(Result, EmptyHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor],
    ValueBuff - SizeOf(TImageDosHeader)));


  // IMAGE_NT_HEADERS
  Cursor := ValueBuff;
  AddString(Result, NT_HEADERS);
  AddString(Result, 'Signature', @Buff[Cursor], dtAnsiString, 4, Cursor);

  // IMAGE_FILE_HEADER
  AddString(Result, FILE_HEADER);
  ValueBuff := PWord(@Buff[Cursor])^;
  AddString(Result, 'Machine', @Buff[Cursor], dtWord, Cursor,
    FileHeaderMachineToStr(ValueBuff));
  NumberOfSections := PWord(@Buff[Cursor])^;
  AddString(Result, 'NumberOfSections', @Buff[Cursor], dtWord, Cursor);
  ValueBuff := PDWORD(@Buff[Cursor])^;
  AddString(Result, 'TimeDateStamp', @Buff[Cursor], dtDword, Cursor,
    FileHeaderTimeStampToStr(ValueBuff));
  AddString(Result, 'PointerToSymbolTable', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NumberOfSymbols', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SizeOfOptionalHeader', @Buff[Cursor], dtWord, Cursor);
  ValueBuff := PWord(@Buff[Cursor])^;
  AddString(Result, 'Characteristics', @Buff[Cursor], dtWord, Cursor,
    FileHeaderCharacteristicsToStr(ValueBuff));

  // IMAGE_OPTIONAL_HEADER_XX
  ValueBuff := PWord(@Buff[Cursor])^;
  Optional32 := ValueBuff = IMAGE_NT_OPTIONAL_HDR32_MAGIC;
  if Optional32 then
    AddString(Result, OPTIONAL_HEADER32)
  else
    AddString(Result, OPTIONAL_HEADER64);
  AddString(Result, 'Magic', @Buff[Cursor], dtWord, Cursor,
    OptionalHeaderMagicToStr(ValueBuff));
  AddString(Result, 'MajorLinkerVersion', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'MinorLinkerVersion', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'SizeOfCode', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SizeOfInitializedData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SizeOfUninitializedData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AddressOfEntryPoint', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'BaseOfCode', @Buff[Cursor], dtDword, Cursor);
  if Optional32 then
  begin
    AddString(Result, 'BaseOfData', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'ImageBase', @Buff[Cursor], dtDword, Cursor);
  end
  else
    AddString(Result, 'ImageBase', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SectionAlignment', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'FileAlignment', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'MajorOperatingSystemVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'MinorOperatingSystemVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'MajorImageVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'MinorImageVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'MajorSubsystemVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'MinorSubsystemVersion', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'Win32VersionValue', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SizeOfImage', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'SizeOfHeaders', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'CheckSum', @Buff[Cursor], dtDword, Cursor);
  ValueBuff := PWord(@Buff[Cursor])^;
  AddString(Result, 'Subsystem', @Buff[Cursor], dtWord, Cursor,
    OptionalHeaderSubsystemToStr(ValueBuff));
  AddString(Result, 'DllCharacteristics', @Buff[Cursor], dtWord, Cursor);
  if Optional32 then
  begin
    AddString(Result, 'SizeOfStackReserve', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'SizeOfStackCommit', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'SizeOfHeapReserve', @Buff[Cursor], dtDword, Cursor);
    AddString(Result, 'SizeOfHeapCommit', @Buff[Cursor], dtDword, Cursor);
  end
  else
  begin
    AddString(Result, 'SizeOfStackReserve', @Buff[Cursor], dtInt64, Cursor);
    AddString(Result, 'SizeOfStackCommit', @Buff[Cursor], dtInt64, Cursor);
    AddString(Result, 'SizeOfHeapReserve', @Buff[Cursor], dtInt64, Cursor);
    AddString(Result, 'SizeOfHeapCommit', @Buff[Cursor], dtInt64, Cursor);
  end;
  AddString(Result, 'LoaderFlags', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NumberOfRvaAndSizes', @Buff[Cursor], dtDword, Cursor);

  // IMAGE_DATA_DIRECTORY
  AddString(Result, DATA_DIRECTORY);
  for I := 0 to IMAGE_NUMBEROF_DIRECTORY_ENTRIES - 1 do
    DumpDataDirectory(I);

  // IMAGE_SECTION_HEADERS
  AddString(Result, SECTION_HEADERS);
  for I := 0 to NumberOfSections - 1 do
  begin
    if I > 0 then
      AddString(Result, EmptyHeader);
    DumpSection;
  end;

  // ��������� ������
  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;

function DumpThread64(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, RegionSize, Cursor: NativeUInt;
begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  Cursor := 0;
  AddString(Result, TEB_Header);
  AddString(Result, 'SEH Chain', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'StackBase', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'StackLimit', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'SubSystemTib', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'FiberData', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'ArbitraryUserPointer', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'Self', @Buff[Cursor], dtInt64, Cursor);

  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;

function DumpThread32(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, RegionSize, Cursor: NativeUInt;
begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  Cursor := 0;
  AddString(Result, TEB_Header);

  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;

procedure DumpKSystemTime(var OutValue: string; const Description: string;
  Address: Pointer; var Cursor: NativeUInt);
begin
  AddString(OutValue, Description + '.LowPart', Address, dtDword, Cursor);
  Address := PByte(Address) + 4;
  AddString(OutValue, Description + '.High1Time', Address, dtDword, Cursor);
  Address := PByte(Address) + 4;
  AddString(OutValue, Description + '.High2Time', Address, dtDword, Cursor);
end;

function NtProductTypeToStr(Value: DWORD): string;
begin
  case Value of
    VER_NT_WORKSTATION: Result := 'VER_NT_WORKSTATION';
    VER_NT_DOMAIN_CONTROLLER: Result := 'VER_NT_DOMAIN_CONTROLLER';
    VER_NT_SERVER: Result := 'VER_NT_SERVER';
  else
    Result := '';
  end;
end;

function DumpKUserSharedData(Process: THandle; Address: Pointer): string;
var
  Buff: array of Byte;
  Size, RegionSize, Cursor: NativeUInt;
  ValueBuff: DWORD;
begin
  Result := '';
  CurerntAddr := Address;
  Size := 4096;
  SetLength(Buff, Size);
  if not ReadProcessData(Process, Address, @Buff[0],
    Size, RegionSize, rcReadAllwais) then Exit;
  Cursor := 0;
  AddString(Result, KUSER);
  AddString(Result, 'TickCountLowDeprecated', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TickCountMultiplier', @Buff[Cursor], dtDword, Cursor);
  DumpKSystemTime(Result, 'InterruptTime', @Buff[Cursor], Cursor);
  DumpKSystemTime(Result, 'SystemTime', @Buff[Cursor], Cursor);
  DumpKSystemTime(Result, 'TimeZoneBias', @Buff[Cursor], Cursor);
  AddString(Result, 'ImageNumberLow', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'ImageNumberHigh', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'NtSystemRoot', @Buff[Cursor], dtString, 520, Cursor);
  AddString(Result, EmptyHeader);
  AddString(Result, 'MaxStackTraceDepth', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'CryptoExponent', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'TimeZoneId', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'LargePageMinimum', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AitSamplingValue', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'AppCompatFlag', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'RNGSeedVersion', @Buff[Cursor], dtInt64, Cursor);
  AddString(Result, 'GlobalValidationRunlevel', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'Reserved2', @Buff[Cursor], dtInt64, Cursor);
  ValueBuff := PDWORD(@Buff[Cursor])^;
  AddString(Result, 'NtProductType', @Buff[Cursor], dtDword, Cursor,
    NtProductTypeToStr(ValueBuff));
  AddString(Result, 'ProductTypeIsValid', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'Reserved0', @Buff[Cursor], dtByte, Cursor);
  AddString(Result, 'NativeProcessorArchitecture', @Buff[Cursor], dtWord, Cursor);
  AddString(Result, 'NtMajorVersion', @Buff[Cursor], dtDword, Cursor);
  AddString(Result, 'NtMinorVersion', @Buff[Cursor], dtDword, Cursor);

  AddString(Result, MemoryDumpHeader);
  AddString(Result, ByteToHexStr(ULONG_PTR(Address) + Cursor, @Buff[Cursor], Size - Cursor));
end;


end.
