; CPack install script designed for a nmake build

;--------------------------------
; You must define these values

  !define VERSION "1.5.0"
  !define PATCH  "0"
  !define INST_DIR "munt-${VERSION}-win32"

;--------------------------------
;Variables

  Var MUI_TEMP
  Var STARTMENU_FOLDER
  Var SV_ALLUSERS
  Var START_MENU
  Var DO_NOT_ADD_TO_PATH
  Var ADD_TO_PATH_ALL_USERS
  Var ADD_TO_PATH_CURRENT_USER
  Var INSTALL_DESKTOP
  Var IS_DEFAULT_INSTALLDIR
;--------------------------------
;Include Modern UI

  !include "MUI.nsh"

  ;Default installation folder
  InstallDir "$PROGRAMFILES\munt"

;--------------------------------
;General

  ;Name and file
  Name "Munt - MT-32 Sound Module Emulator"
  OutFile "munt-${VERSION}-win32.exe"

  ;Set compression
  SetCompressor lzma



  !include Sections.nsh

;--- Component support macros: ---
; The code for the add/remove functionality is from:
;   http://nsis.sourceforge.net/Add/Remove_Functionality
; It has been modified slightly and extended to provide
; inter-component dependencies.
Var AR_SecFlags
Var AR_RegFlags


; Loads the "selected" flag for the section named SecName into the
; variable VarName.
!macro LoadSectionSelectedIntoVar SecName VarName
 SectionGetFlags ${${SecName}} $${VarName}
 IntOp $${VarName} $${VarName} & ${SF_SELECTED}  ;Turn off all other bits
!macroend

; Loads the value of a variable... can we get around this?
!macro LoadVar VarName
  IntOp $R0 0 + $${VarName}
!macroend

; Sets the value of a variable
!macro StoreVar VarName IntValue
  IntOp $${VarName} 0 + ${IntValue}
!macroend

!macro InitSection SecName
  ;  This macro reads component installed flag from the registry and
  ;changes checked state of the section on the components page.
  ;Input: section index constant name specified in Section command.

  ClearErrors
  ;Reading component status from registry
  ReadRegDWORD $AR_RegFlags HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}\Components\${SecName}" "Installed"
  IfErrors "default_${SecName}"
    ;Status will stay default if registry value not found
    ;(component was never installed)
  IntOp $AR_RegFlags $AR_RegFlags & ${SF_SELECTED} ;Turn off all other bits
  SectionGetFlags ${${SecName}} $AR_SecFlags  ;Reading default section flags
  IntOp $AR_SecFlags $AR_SecFlags & 0xFFFE  ;Turn lowest (enabled) bit off
  IntOp $AR_SecFlags $AR_RegFlags | $AR_SecFlags      ;Change lowest bit

  ; Note whether this component was installed before
  !insertmacro StoreVar ${SecName}_was_installed $AR_RegFlags
  IntOp $R0 $AR_RegFlags & $AR_RegFlags

  ;Writing modified flags
  SectionSetFlags ${${SecName}} $AR_SecFlags

 "default_${SecName}:"
 !insertmacro LoadSectionSelectedIntoVar ${SecName} ${SecName}_selected
!macroend

!macro FinishSection SecName
  ;  This macro reads section flag set by user and removes the section
  ;if it is not selected.
  ;Then it writes component installed flag to registry
  ;Input: section index constant name specified in Section command.

  SectionGetFlags ${${SecName}} $AR_SecFlags  ;Reading section flags
  ;Checking lowest bit:
  IntOp $AR_SecFlags $AR_SecFlags & ${SF_SELECTED}
  IntCmp $AR_SecFlags 1 "leave_${SecName}"
    ;Section is not selected:
    ;Calling Section uninstall macro and writing zero installed flag
    !insertmacro "Remove_${${SecName}}"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}\Components\${SecName}" \
  "Installed" 0
    Goto "exit_${SecName}"

 "leave_${SecName}:"
    ;Section is selected:
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}\Components\${SecName}" \
  "Installed" 1

 "exit_${SecName}:"
!macroend

!macro RemoveSection SecName
  ;  This macro is used to call section's Remove_... macro
  ;from the uninstaller.
  ;Input: section index constant name specified in Section command.

  !insertmacro "Remove_${${SecName}}"
!macroend

; Determine whether the selection of SecName changed
!macro MaybeSelectionChanged SecName
  !insertmacro LoadVar ${SecName}_selected
  SectionGetFlags ${${SecName}} $R1
  IntOp $R1 $R1 & ${SF_SELECTED} ;Turn off all other bits

  ; See if the status has changed:
  IntCmp $R0 $R1 "${SecName}_unchanged"
  !insertmacro LoadSectionSelectedIntoVar ${SecName} ${SecName}_selected

  IntCmp $R1 ${SF_SELECTED} "${SecName}_was_selected"
  !insertmacro "Deselect_required_by_${SecName}"
  goto "${SecName}_unchanged"

  "${SecName}_was_selected:"
  !insertmacro "Select_${SecName}_depends"

  "${SecName}_unchanged:"
!macroend
;--- End of Add/Remove macros ---

;--------------------------------
;Interface Settings

  !define MUI_HEADERIMAGE
  !define MUI_ABORTWARNING

;--------------------------------
; path functions

!verbose 3
!include "WinMessages.NSH"
!verbose 4

;----------------------------------------
; based upon a script of "Written by KiCHiK 2003-01-18 05:57:02"
;----------------------------------------
!verbose 3
!include "WinMessages.NSH"
!verbose 4
;====================================================
; get_NT_environment
;     Returns: the selected environment
;     Output : head of the stack
;====================================================
!macro select_NT_profile UN
Function ${UN}select_NT_profile
   StrCmp $ADD_TO_PATH_ALL_USERS "1" 0 environment_single
      DetailPrint "Selected environment for all users"
      Push "all"
      Return
   environment_single:
      DetailPrint "Selected environment for current user only."
      Push "current"
      Return
FunctionEnd
!macroend
!insertmacro select_NT_profile ""
!insertmacro select_NT_profile "un."
;----------------------------------------------------
!define NT_current_env 'HKCU "Environment"'
!define NT_all_env     'HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'

!ifndef WriteEnvStr_RegKey
  !ifdef ALL_USERS
    !define WriteEnvStr_RegKey \
       'HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
  !else
    !define WriteEnvStr_RegKey 'HKCU "Environment"'
  !endif
!endif

; AddToPath - Adds the given dir to the search path.
;        Input - head of the stack
;        Note - Win9x systems requires reboot

Function AddToPath
  Exch $0
  Push $1
  Push $2
  Push $3

  # don't add if the path doesn't exist
  IfFileExists "$0\*.*" "" AddToPath_done

  ReadEnvStr $1 PATH
  ; if the path is too long for a NSIS variable NSIS will return a 0
  ; length string.  If we find that, then warn and skip any path
  ; modification as it will trash the existing path.
  StrLen $2 $1
  IntCmp $2 0 CheckPathLength_ShowPathWarning CheckPathLength_Done CheckPathLength_Done
    CheckPathLength_ShowPathWarning:
    Messagebox MB_OK|MB_ICONEXCLAMATION "Warning! PATH too long installer unable to modify PATH!"
    Goto AddToPath_done
  CheckPathLength_Done:
  Push "$1;"
  Push "$0;"
  Call StrStr
  Pop $2
  StrCmp $2 "" "" AddToPath_done
  Push "$1;"
  Push "$0\;"
  Call StrStr
  Pop $2
  StrCmp $2 "" "" AddToPath_done
  GetFullPathName /SHORT $3 $0
  Push "$1;"
  Push "$3;"
  Call StrStr
  Pop $2
  StrCmp $2 "" "" AddToPath_done
  Push "$1;"
  Push "$3\;"
  Call StrStr
  Pop $2
  StrCmp $2 "" "" AddToPath_done

  Call IsNT
  Pop $1
  StrCmp $1 1 AddToPath_NT
    ; Not on NT
    StrCpy $1 $WINDIR 2
    FileOpen $1 "$1\autoexec.bat" a
    FileSeek $1 -1 END
    FileReadByte $1 $2
    IntCmp $2 26 0 +2 +2 # DOS EOF
      FileSeek $1 -1 END # write over EOF
    FileWrite $1 "$\r$\nSET PATH=%PATH%;$3$\r$\n"
    FileClose $1
    SetRebootFlag true
    Goto AddToPath_done

  AddToPath_NT:
    StrCmp $ADD_TO_PATH_ALL_USERS "1" ReadAllKey
      ReadRegStr $1 ${NT_current_env} "PATH"
      Goto DoTrim
    ReadAllKey:
      ReadRegStr $1 ${NT_all_env} "PATH"
    DoTrim:
    StrCmp $1 "" AddToPath_NTdoIt
      Push $1
      Call Trim
      Pop $1
      StrCpy $0 "$1;$0"
    AddToPath_NTdoIt:
      StrCmp $ADD_TO_PATH_ALL_USERS "1" WriteAllKey
        WriteRegExpandStr ${NT_current_env} "PATH" $0
        Goto DoSend
      WriteAllKey:
        WriteRegExpandStr ${NT_all_env} "PATH" $0
      DoSend:
      SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000

  AddToPath_done:
    Pop $3
    Pop $2
    Pop $1
    Pop $0
FunctionEnd


; RemoveFromPath - Remove a given dir from the path
;     Input: head of the stack

Function un.RemoveFromPath
  Exch $0
  Push $1
  Push $2
  Push $3
  Push $4
  Push $5
  Push $6

  IntFmt $6 "%c" 26 # DOS EOF

  Call un.IsNT
  Pop $1
  StrCmp $1 1 unRemoveFromPath_NT
    ; Not on NT
    StrCpy $1 $WINDIR 2
    FileOpen $1 "$1\autoexec.bat" r
    GetTempFileName $4
    FileOpen $2 $4 w
    GetFullPathName /SHORT $0 $0
    StrCpy $0 "SET PATH=%PATH%;$0"
    Goto unRemoveFromPath_dosLoop

    unRemoveFromPath_dosLoop:
      FileRead $1 $3
      StrCpy $5 $3 1 -1 # read last char
      StrCmp $5 $6 0 +2 # if DOS EOF
        StrCpy $3 $3 -1 # remove DOS EOF so we can compare
      StrCmp $3 "$0$\r$\n" unRemoveFromPath_dosLoopRemoveLine
      StrCmp $3 "$0$\n" unRemoveFromPath_dosLoopRemoveLine
      StrCmp $3 "$0" unRemoveFromPath_dosLoopRemoveLine
      StrCmp $3 "" unRemoveFromPath_dosLoopEnd
      FileWrite $2 $3
      Goto unRemoveFromPath_dosLoop
      unRemoveFromPath_dosLoopRemoveLine:
        SetRebootFlag true
        Goto unRemoveFromPath_dosLoop

    unRemoveFromPath_dosLoopEnd:
      FileClose $2
      FileClose $1
      StrCpy $1 $WINDIR 2
      Delete "$1\autoexec.bat"
      CopyFiles /SILENT $4 "$1\autoexec.bat"
      Delete $4
      Goto unRemoveFromPath_done

  unRemoveFromPath_NT:
    StrCmp $ADD_TO_PATH_ALL_USERS "1" unReadAllKey
      ReadRegStr $1 ${NT_current_env} "PATH"
      Goto unDoTrim
    unReadAllKey:
      ReadRegStr $1 ${NT_all_env} "PATH"
    unDoTrim:
    StrCpy $5 $1 1 -1 # copy last char
    StrCmp $5 ";" +2 # if last char != ;
      StrCpy $1 "$1;" # append ;
    Push $1
    Push "$0;"
    Call un.StrStr ; Find `$0;` in $1
    Pop $2 ; pos of our dir
    StrCmp $2 "" unRemoveFromPath_done
      ; else, it is in path
      # $0 - path to add
      # $1 - path var
      StrLen $3 "$0;"
      StrLen $4 $2
      StrCpy $5 $1 -$4 # $5 is now the part before the path to remove
      StrCpy $6 $2 "" $3 # $6 is now the part after the path to remove
      StrCpy $3 $5$6

      StrCpy $5 $3 1 -1 # copy last char
      StrCmp $5 ";" 0 +2 # if last char == ;
        StrCpy $3 $3 -1 # remove last char

      StrCmp $ADD_TO_PATH_ALL_USERS "1" unWriteAllKey
        WriteRegExpandStr ${NT_current_env} "PATH" $3
        Goto unDoSend
      unWriteAllKey:
        WriteRegExpandStr ${NT_all_env} "PATH" $3
      unDoSend:
      SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000

  unRemoveFromPath_done:
    Pop $6
    Pop $5
    Pop $4
    Pop $3
    Pop $2
    Pop $1
    Pop $0
FunctionEnd

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Uninstall sutff
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

###########################################
#            Utility Functions            #
###########################################

;====================================================
; IsNT - Returns 1 if the current system is NT, 0
;        otherwise.
;     Output: head of the stack
;====================================================
; IsNT
; no input
; output, top of the stack = 1 if NT or 0 if not
;
; Usage:
;   Call IsNT
;   Pop $R0
;  ($R0 at this point is 1 or 0)

!macro IsNT un
Function ${un}IsNT
  Push $0
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" CurrentVersion
  StrCmp $0 "" 0 IsNT_yes
  ; we are not NT.
  Pop $0
  Push 0
  Return

  IsNT_yes:
    ; NT!!!
    Pop $0
    Push 1
FunctionEnd
!macroend
!insertmacro IsNT ""
!insertmacro IsNT "un."

; StrStr
; input, top of stack = string to search for
;        top of stack-1 = string to search in
; output, top of stack (replaces with the portion of the string remaining)
; modifies no other variables.
;
; Usage:
;   Push "this is a long ass string"
;   Push "ass"
;   Call StrStr
;   Pop $R0
;  ($R0 at this point is "ass string")

!macro StrStr un
Function ${un}StrStr
Exch $R1 ; st=haystack,old$R1, $R1=needle
  Exch    ; st=old$R1,haystack
  Exch $R2 ; st=old$R1,old$R2, $R2=haystack
  Push $R3
  Push $R4
  Push $R5
  StrLen $R3 $R1
  StrCpy $R4 0
  ; $R1=needle
  ; $R2=haystack
  ; $R3=len(needle)
  ; $R4=cnt
  ; $R5=tmp
  loop:
    StrCpy $R5 $R2 $R3 $R4
    StrCmp $R5 $R1 done
    StrCmp $R5 "" done
    IntOp $R4 $R4 + 1
    Goto loop
done:
  StrCpy $R1 $R2 "" $R4
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Exch $R1
FunctionEnd
!macroend
!insertmacro StrStr ""
!insertmacro StrStr "un."

Function Trim ; Added by Pelaca
	Exch $R1
	Push $R2
Loop:
	StrCpy $R2 "$R1" 1 -1
	StrCmp "$R2" " " RTrim
	StrCmp "$R2" "$\n" RTrim
	StrCmp "$R2" "$\r" RTrim
	StrCmp "$R2" ";" RTrim
	GoTo Done
RTrim:
	StrCpy $R1 "$R1" -1
	Goto Loop
Done:
	Pop $R2
	Exch $R1
FunctionEnd

Function ConditionalAddToRegisty
  Pop $0
  Pop $1
  StrCmp "$0" "" ConditionalAddToRegisty_EmptyString
    WriteRegStr SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" \
    "$1" "$0"
    ;MessageBox MB_OK "Set Registry: '$1' to '$0'"
    DetailPrint "Set install registry entry: '$1' to '$0'"
  ConditionalAddToRegisty_EmptyString:
FunctionEnd

;--------------------------------

!ifdef CPACK_USES_DOWNLOAD
Function DownloadFile
    IfFileExists $INSTDIR\* +2
    CreateDirectory $INSTDIR
    Pop $0

    ; Skip if already downloaded
    IfFileExists $INSTDIR\$0 0 +2
    Return

    StrCpy $1 ""

  try_again:
    NSISdl::download "$1/$0" "$INSTDIR\$0"

    Pop $1
    StrCmp $1 "success" success
    StrCmp $1 "Cancelled" cancel
    MessageBox MB_OK "Download failed: $1"
  cancel:
    Return
  success:
FunctionEnd
!endif

;--------------------------------
; Installation types


;--------------------------------
; Component sections


;--------------------------------
; Define some macro setting for the gui





;--------------------------------
;Pages
  !insertmacro MUI_PAGE_WELCOME

  !insertmacro MUI_PAGE_LICENSE "C:/Qt/munt/mt32emu_qt/COPYING.txt"
  Page custom InstallOptionsPage
  !insertmacro MUI_PAGE_DIRECTORY

  ;Start Menu Folder Page Configuration
  !define MUI_STARTMENUPAGE_REGISTRY_ROOT "SHCTX"
  !define MUI_STARTMENUPAGE_REGISTRY_KEY "Software\muntemu.org\munt"
  !define MUI_STARTMENUPAGE_REGISTRY_VALUENAME "Start Menu Folder"
  !insertmacro MUI_PAGE_STARTMENU Application $STARTMENU_FOLDER

  

  !insertmacro MUI_PAGE_INSTFILES
  !insertmacro MUI_PAGE_FINISH

  !insertmacro MUI_UNPAGE_CONFIRM
  !insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------
;Languages

  !insertmacro MUI_LANGUAGE "English" ;first language is the default language
  !insertmacro MUI_LANGUAGE "Albanian"
  !insertmacro MUI_LANGUAGE "Arabic"
  !insertmacro MUI_LANGUAGE "Basque"
  !insertmacro MUI_LANGUAGE "Belarusian"
  !insertmacro MUI_LANGUAGE "Bosnian"
  !insertmacro MUI_LANGUAGE "Breton"
  !insertmacro MUI_LANGUAGE "Bulgarian"
  !insertmacro MUI_LANGUAGE "Croatian"
  !insertmacro MUI_LANGUAGE "Czech"
  !insertmacro MUI_LANGUAGE "Danish"
  !insertmacro MUI_LANGUAGE "Dutch"
  !insertmacro MUI_LANGUAGE "Estonian"
  !insertmacro MUI_LANGUAGE "Farsi"
  !insertmacro MUI_LANGUAGE "Finnish"
  !insertmacro MUI_LANGUAGE "French"
  !insertmacro MUI_LANGUAGE "German"
  !insertmacro MUI_LANGUAGE "Greek"
  !insertmacro MUI_LANGUAGE "Hebrew"
  !insertmacro MUI_LANGUAGE "Hungarian"
  !insertmacro MUI_LANGUAGE "Icelandic"
  !insertmacro MUI_LANGUAGE "Indonesian"
  !insertmacro MUI_LANGUAGE "Irish"
  !insertmacro MUI_LANGUAGE "Italian"
  !insertmacro MUI_LANGUAGE "Japanese"
  !insertmacro MUI_LANGUAGE "Korean"
  !insertmacro MUI_LANGUAGE "Kurdish"
  !insertmacro MUI_LANGUAGE "Latvian"
  !insertmacro MUI_LANGUAGE "Lithuanian"
  !insertmacro MUI_LANGUAGE "Luxembourgish"
  !insertmacro MUI_LANGUAGE "Macedonian"
  !insertmacro MUI_LANGUAGE "Malay"
  !insertmacro MUI_LANGUAGE "Mongolian"
  !insertmacro MUI_LANGUAGE "Norwegian"
  !insertmacro MUI_LANGUAGE "Polish"
  !insertmacro MUI_LANGUAGE "Portuguese"
  !insertmacro MUI_LANGUAGE "PortugueseBR"
  !insertmacro MUI_LANGUAGE "Romanian"
  !insertmacro MUI_LANGUAGE "Russian"
  !insertmacro MUI_LANGUAGE "Serbian"
  !insertmacro MUI_LANGUAGE "SerbianLatin"
  !insertmacro MUI_LANGUAGE "SimpChinese"
  !insertmacro MUI_LANGUAGE "Slovak"
  !insertmacro MUI_LANGUAGE "Slovenian"
  !insertmacro MUI_LANGUAGE "Spanish"
  !insertmacro MUI_LANGUAGE "Swedish"
  !insertmacro MUI_LANGUAGE "Thai"
  !insertmacro MUI_LANGUAGE "TradChinese"
  !insertmacro MUI_LANGUAGE "Turkish"
  !insertmacro MUI_LANGUAGE "Ukrainian"
  !insertmacro MUI_LANGUAGE "Welsh"


;--------------------------------
;Reserve Files

  ;These files should be inserted before other files in the data block
  ;Keep these lines before any File command
  ;Only for solid compression (by default, solid compression is enabled for BZIP2 and LZMA)

  ReserveFile "NSIS.InstallOptions.ini"
  !insertmacro MUI_RESERVEFILE_INSTALLOPTIONS

;--------------------------------
;Installer Sections

Section "-Core installation"
  ;Use the entire tree produced by the INSTALL target.  Keep the
  ;list of directories here in sync with the RMDir commands below.
  SetOutPath "$INSTDIR"
  
  File /r "${INST_DIR}\*.*"

  ;Store installation folder
  WriteRegStr SHCTX "Software\muntemu.org\munt ${VERSION}" "" $INSTDIR

  ;Register MIDI driver
  Exec '"$INSTDIR\bin\mt32emu_win32drv\drvsetup.exe" install'

  ;Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  Push "DisplayName"
  Push "munt ${VERSION}"
  Call ConditionalAddToRegisty
  Push "DisplayVersion"
  Push "${VERSION}"
  Call ConditionalAddToRegisty
  Push "Publisher"
  Push "muntemu.org"
  Call ConditionalAddToRegisty
  Push "UninstallString"
  Push "$INSTDIR\Uninstall.exe"
  Call ConditionalAddToRegisty
  Push "NoRepair"
  Push "1"
  Call ConditionalAddToRegisty

  !ifdef CPACK_NSIS_ADD_REMOVE
  ;Create add/remove functionality
  Push "ModifyPath"
  Push "$INSTDIR\AddRemove.exe"
  Call ConditionalAddToRegisty
  !else
  Push "NoModify"
  Push "1"
  Call ConditionalAddToRegisty
  !endif

  ; Optional registration
  Push "DisplayIcon"
  Push "$INSTDIR\"
  Call ConditionalAddToRegisty
  Push "HelpLink"
  Push ""
  Call ConditionalAddToRegisty
  Push "URLInfoAbout"
  Push ""
  Call ConditionalAddToRegisty
  Push "Contact"
  Push ""
  Call ConditionalAddToRegisty
  !insertmacro MUI_INSTALLOPTIONS_READ $INSTALL_DESKTOP "NSIS.InstallOptions.ini" "Field 5" "State"
  !insertmacro MUI_STARTMENU_WRITE_BEGIN Application

  ;Create shortcuts
  CreateDirectory "$SMPROGRAMS\$STARTMENU_FOLDER"
  CreateShortCut "$SMPROGRAMS\$STARTMENU_FOLDER\Munt MT-32 Sound Module Emulator.lnk" "$INSTDIR\bin\mt32emu-qt.exe"


  CreateShortCut "$SMPROGRAMS\$STARTMENU_FOLDER\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

  ;Read a value from an InstallOptions INI file
  !insertmacro MUI_INSTALLOPTIONS_READ $DO_NOT_ADD_TO_PATH "NSIS.InstallOptions.ini" "Field 2" "State"
  !insertmacro MUI_INSTALLOPTIONS_READ $ADD_TO_PATH_ALL_USERS "NSIS.InstallOptions.ini" "Field 3" "State"
  !insertmacro MUI_INSTALLOPTIONS_READ $ADD_TO_PATH_CURRENT_USER "NSIS.InstallOptions.ini" "Field 4" "State"

  ; Write special uninstall registry entries
  Push "StartMenu"
  Push "$STARTMENU_FOLDER"
  Call ConditionalAddToRegisty
  Push "DoNotAddToPath"
  Push "$DO_NOT_ADD_TO_PATH"
  Call ConditionalAddToRegisty
  Push "AddToPathAllUsers"
  Push "$ADD_TO_PATH_ALL_USERS"
  Call ConditionalAddToRegisty
  Push "AddToPathCurrentUser"
  Push "$ADD_TO_PATH_CURRENT_USER"
  Call ConditionalAddToRegisty
  Push "InstallToDesktop"
  Push "$INSTALL_DESKTOP"
  Call ConditionalAddToRegisty

  !insertmacro MUI_STARTMENU_WRITE_END



SectionEnd

Section "-Add to path"
  Push $INSTDIR\bin
  StrCmp "" "ON" 0 doNotAddToPath
  StrCmp $DO_NOT_ADD_TO_PATH "1" doNotAddToPath 0
    Call AddToPath
  doNotAddToPath:
SectionEnd

;--------------------------------
; Create custom pages
Function InstallOptionsPage
  !insertmacro MUI_HEADER_TEXT "Install Options" "Choose options for installing munt ${VERSION}"
  !insertmacro MUI_INSTALLOPTIONS_DISPLAY "NSIS.InstallOptions.ini"

FunctionEnd

;--------------------------------
; determine admin versus local install
Function un.onInit

  ClearErrors
  UserInfo::GetName
  IfErrors noLM
  Pop $0
  UserInfo::GetAccountType
  Pop $1
  StrCmp $1 "Admin" 0 +3
    SetShellVarContext all
    ;MessageBox MB_OK 'User "$0" is in the Admin group'
    Goto done
  StrCmp $1 "Power" 0 +3
    SetShellVarContext all
    ;MessageBox MB_OK 'User "$0" is in the Power Users group'
    Goto done

  noLM:
    ;Get installation folder from registry if available

  done:

FunctionEnd

;--- Add/Remove callback functions: ---
!macro SectionList MacroName
  ;This macro used to perform operation on multiple sections.
  ;List all of your components in following manner here.

!macroend

Section -FinishComponents
  ;Removes unselected components and writes component status to registry
  !insertmacro SectionList "FinishSection"

!ifdef CPACK_NSIS_ADD_REMOVE
  ; Get the name of the installer executable
  System::Call 'kernel32::GetModuleFileNameA(i 0, t .R0, i 1024) i r1'
  StrCpy $R3 $R0

  ; Strip off the last 13 characters, to see if we have AddRemove.exe
  StrLen $R1 $R0
  IntOp $R1 $R0 - 13
  StrCpy $R2 $R0 13 $R1
  StrCmp $R2 "AddRemove.exe" addremove_installed

  ; We're not running AddRemove.exe, so install it
  CopyFiles $R3 $INSTDIR\AddRemove.exe

  addremove_installed:
!endif
SectionEnd
;--- End of Add/Remove callback functions ---

;--------------------------------
; Component dependencies
Function .onSelChange
  !insertmacro SectionList MaybeSelectionChanged
FunctionEnd

;--------------------------------
;Uninstaller Section

Section "Uninstall"
  ReadRegStr $START_MENU SHCTX \
   "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "StartMenu"
  ;MessageBox MB_OK "Start menu is in: $START_MENU"
  ReadRegStr $DO_NOT_ADD_TO_PATH SHCTX \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "DoNotAddToPath"
  ReadRegStr $ADD_TO_PATH_ALL_USERS SHCTX \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "AddToPathAllUsers"
  ReadRegStr $ADD_TO_PATH_CURRENT_USER SHCTX \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "AddToPathCurrentUser"
  ;MessageBox MB_OK "Add to path: $DO_NOT_ADD_TO_PATH all users: $ADD_TO_PATH_ALL_USERS"
  ReadRegStr $INSTALL_DESKTOP SHCTX \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "InstallToDesktop"
  ;MessageBox MB_OK "Install to desktop: $INSTALL_DESKTOP "


  ;Unregister MIDI driver
  ExecWait '"$INSTDIR\bin\mt32emu_win32drv\drvsetup.exe" uninstall'

  ;Remove files we installed.
  ;Keep the list of directories here in sync with the File commands above.
  Delete "$INSTDIR\bin\intl.dll"
  Delete "$INSTDIR\bin\libglib-2.0-0.dll"
  Delete "$INSTDIR\bin\libsoxr.dll"
  Delete "$INSTDIR\bin\portaudio_x86.dll"
  Delete "$INSTDIR\bin\QtCore4.dll"
  Delete "$INSTDIR\bin\QtGui4.dll"
  Delete "$INSTDIR\bin\QtMultimedia4.dll"
  Delete "$INSTDIR\bin\mt32emu-qt.exe"
  Delete "$INSTDIR\bin\mt32emu-smf2wav.exe"
  Delete "$INSTDIR\bin\imageformats\qgif4.dll"
  Delete "$INSTDIR\bin\mt32emu_win32drv\drvsetup.exe"
  Delete "$INSTDIR\bin\mt32emu_win32drv\mt32emu.dll"
  Delete "$INSTDIR\bin\mt32emu_win32drv\mt32emu.inf"
  Delete "$INSTDIR\docs\mt32emu\AUTHORS.txt"
  Delete "$INSTDIR\docs\mt32emu\COPYING.LESSER.txt"
  Delete "$INSTDIR\docs\mt32emu\COPYING.txt"
  Delete "$INSTDIR\docs\mt32emu\NEWS.txt"
  Delete "$INSTDIR\docs\mt32emu\README.txt"
  Delete "$INSTDIR\docs\mt32emu\TODO.txt"
  Delete "$INSTDIR\docs\mt32emu_qt\AUTHORS.txt"
  Delete "$INSTDIR\docs\mt32emu_qt\COPYING.txt"
  Delete "$INSTDIR\docs\mt32emu_qt\NEWS.txt"
  Delete "$INSTDIR\docs\mt32emu_qt\README.txt"
  Delete "$INSTDIR\docs\mt32emu_qt\TODO.txt"
  Delete "$INSTDIR\docs\mt32emu_smf2wav\AUTHORS.txt"
  Delete "$INSTDIR\docs\mt32emu_smf2wav\COPYING.txt"
  Delete "$INSTDIR\docs\mt32emu_smf2wav\README.txt"
  Delete "$INSTDIR\docs\mt32emu_win32drv\COPYING.txt"
  Delete "$INSTDIR\docs\mt32emu_win32drv\COPYING.LESSER.txt"
  Delete "$INSTDIR\docs\mt32emu_win32drv\NEWS.txt"
  Delete "$INSTDIR\docs\mt32emu_win32drv\README.txt"

  RMDir "$INSTDIR\bin\imageformats"
  RMDir "$INSTDIR\bin\mt32emu_win32drv"
  RMDir "$INSTDIR\bin"
  RMDir "$INSTDIR\docs\mt32emu"
  RMDir "$INSTDIR\docs\mt32emu_qt"
  RMDir "$INSTDIR\docs\mt32emu_smf2wav"
  RMDir "$INSTDIR\docs\mt32emu_win32drv"
  RMDir "$INSTDIR\docs"


!ifdef CPACK_NSIS_ADD_REMOVE
  ;Remove the add/remove program
  Delete "$INSTDIR\AddRemove.exe"
!endif

  ;Remove the uninstaller itself.
  Delete "$INSTDIR\Uninstall.exe"
  DeleteRegKey SHCTX "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}"

  ;Remove the installation directory if it is empty.
  RMDir "$INSTDIR"

  ; Remove the registry entries.
  DeleteRegKey SHCTX "Software\muntemu.org\munt ${VERSION}"

  ; Removes all optional components
  !insertmacro SectionList "RemoveSection"

  !insertmacro MUI_STARTMENU_GETFOLDER Application $MUI_TEMP

  Delete "$SMPROGRAMS\$MUI_TEMP\Uninstall.lnk"
  Delete "$SMPROGRAMS\$MUI_TEMP\Munt MT-32 Sound Module Emulator.lnk"



  ;Delete empty start menu parent diretories
  StrCpy $MUI_TEMP "$SMPROGRAMS\$MUI_TEMP"

  startMenuDeleteLoop:
    ClearErrors
    RMDir $MUI_TEMP
    GetFullPathName $MUI_TEMP "$MUI_TEMP\.."

    IfErrors startMenuDeleteLoopDone

    StrCmp "$MUI_TEMP" "$SMPROGRAMS" startMenuDeleteLoopDone startMenuDeleteLoop
  startMenuDeleteLoopDone:

  ; If the user changed the shortcut, then untinstall may not work. This should
  ; try to fix it.
  StrCpy $MUI_TEMP "$START_MENU"
  Delete "$SMPROGRAMS\$MUI_TEMP\Uninstall.lnk"


  ;Delete empty start menu parent diretories
  StrCpy $MUI_TEMP "$SMPROGRAMS\$MUI_TEMP"

  secondStartMenuDeleteLoop:
    ClearErrors
    RMDir $MUI_TEMP
    GetFullPathName $MUI_TEMP "$MUI_TEMP\.."

    IfErrors secondStartMenuDeleteLoopDone

    StrCmp "$MUI_TEMP" "$SMPROGRAMS" secondStartMenuDeleteLoopDone secondStartMenuDeleteLoop
  secondStartMenuDeleteLoopDone:

  DeleteRegKey /ifempty SHCTX "Software\muntemu.org\munt ${VERSION}"

  Push $INSTDIR\bin
  StrCmp $DO_NOT_ADD_TO_PATH_ "1" doNotRemoveFromPath 0
    Call un.RemoveFromPath
  doNotRemoveFromPath:
SectionEnd

;--------------------------------
; determine admin versus local install
; Is install for "AllUsers" or "JustMe"?
; Default to "JustMe" - set to "AllUsers" if admin or on Win9x
; This function is used for the very first "custom page" of the installer.
; This custom page does not show up visibly, but it executes prior to the
; first visible page and sets up $INSTDIR properly...
; Choose different default installation folder based on SV_ALLUSERS...
; "Program Files" for AllUsers, "My Documents" for JustMe...

Function .onInit
  StrCmp "" "ON" 0 inst

  ReadRegStr $0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\munt ${VERSION}" "UninstallString"
  StrCmp $0 "" inst

  MessageBox MB_YESNOCANCEL|MB_ICONEXCLAMATION \
  "munt ${VERSION} is already installed. $\n$\nDo you want to uninstall the old version before installing the new one?" \
  IDYES uninst IDNO inst
  Abort

;Run the uninstaller
uninst:
  ClearErrors
  ExecWait '$0 _?=$INSTDIR' ;Do not copy the uninstaller to a temp file

  IfErrors uninst_failed inst
uninst_failed:
  MessageBox MB_OK|MB_ICONSTOP "Uninstall failed."
  Abort


inst:
  ; Reads components status for registry
  !insertmacro SectionList "InitSection"

  ; check to see if /D has been used to change
  ; the install directory by comparing it to the
  ; install directory that is expected to be the
  ; default
  StrCpy $IS_DEFAULT_INSTALLDIR 0
  StrCmp "$INSTDIR" "$PROGRAMFILES\munt-${VERSION}" 0 +2
    StrCpy $IS_DEFAULT_INSTALLDIR 1

  StrCpy $SV_ALLUSERS "JustMe"
  ; if default install dir then change the default
  ; if it is installed for JustMe
  StrCmp "$IS_DEFAULT_INSTALLDIR" "1" 0 +2
    StrCpy $INSTDIR "$DOCUMENTS\munt-${VERSION}"

  ClearErrors
  UserInfo::GetName
  IfErrors noLM
  Pop $0
  UserInfo::GetAccountType
  Pop $1
  StrCmp $1 "Admin" 0 +4
    SetShellVarContext all
    ;MessageBox MB_OK 'User "$0" is in the Admin group'
    StrCpy $SV_ALLUSERS "AllUsers"
    Goto done
  StrCmp $1 "Power" 0 +4
    SetShellVarContext all
    ;MessageBox MB_OK 'User "$0" is in the Power Users group'
    StrCpy $SV_ALLUSERS "AllUsers"
    Goto done

  noLM:
    StrCpy $SV_ALLUSERS "AllUsers"
    ;Get installation folder from registry if available

  done:
  StrCmp $SV_ALLUSERS "AllUsers" 0 +3
    StrCmp "$IS_DEFAULT_INSTALLDIR" "1" 0 +2
      StrCpy $INSTDIR "$PROGRAMFILES\munt-${VERSION}"

  StrCmp "" "ON" 0 noOptionsPage
    !insertmacro MUI_INSTALLOPTIONS_EXTRACT "NSIS.InstallOptions.ini"

  noOptionsPage:
FunctionEnd
