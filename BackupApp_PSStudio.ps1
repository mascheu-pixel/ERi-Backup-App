#Requires -Version 5.1
#==============================================================================
#  Robocopy Backup  -  PowerShell Studio Format
#  Version  : 1.6.8.5
#  Author   : schremar:ITServices
#  Copyright: (c) 2026 schremar.com
#==============================================================================

#region ── Assemblies ──────────────────────────────────────────────────────────
# Echter Monitor-DPI via GetDpiForMonitor (shcore.dll) – unabhaengig vom DPI-Awareness-Modus.
# Funktioniert auch ohne .exe.config-Datei.
if (-not ('MonitorDpi' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MonitorDpi {
    [DllImport("shcore.dll")]
    static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll")]
    static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
    public static uint Get(IntPtr hwnd) {
        IntPtr mon = MonitorFromWindow(hwnd, 2); // MONITOR_DEFAULTTONEAREST
        uint x, y;
        return (GetDpiForMonitor(mon, 0, out x, out y) == 0) ? x : 96u; // MDT_EFFECTIVE_DPI=0
    }
}
'@
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Moderner Vista-Dialog via COM (Ordner-Picker + Datei-Speichern/-Oeffnen mit erzwungenem Startordner)
if (-not ('VistaFolderPicker' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IShellItemVFP {
    void _s01(); void _s02();
    [PreserveSig] int GetDisplayName(
        uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
    void _s04(); void _s05();
}

[ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFileDialogVFP {
    [PreserveSig] int Show(IntPtr hwnd);
    void _s02(); void _s03(); void _s04(); void _s05(); void _s06();
    [PreserveSig] int SetOptions(uint fos);
    [PreserveSig] int GetOptions(out uint pfos);
    [PreserveSig] int SetDefaultFolder(IShellItemVFP psi);               // Startordner (ohne Shell-Override)
    [PreserveSig] int SetFolder(IShellItemVFP psi);                     // erzwingt Startordner
    void _s11(); void _s12();                                           // GetFolder, GetCurrentSelection
    [PreserveSig] int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
    void _s14();                                                        // GetFileName
    [PreserveSig] int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
    void _s16(); void _s17();
    [PreserveSig] int GetResult(out IShellItemVFP ppsi);
    void _s19();                                                        // AddPlace
    [PreserveSig] int SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string ext);
    void _s21(); void _s22(); void _s23(); void _s24();
}

public static class VistaFolderPicker {
    private static readonly Guid CLSID_FO =
        new Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7"); // IFileOpenDialog
    private static readonly Guid CLSID_FS =
        new Guid("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B"); // IFileSaveDialog
    private static readonly Guid IID_SI =
        new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHCreateItemFromParsingName(
        string path, IntPtr pbc, ref Guid riid, out IShellItemVFP ppv);

    private static IFileDialogVFP MakeDialog(Guid clsid, string title, string folder, uint opts) {
        var dlg = (IFileDialogVFP)Activator.CreateInstance(Type.GetTypeFromCLSID(clsid));
        uint cur; dlg.GetOptions(out cur);
        dlg.SetOptions(cur | opts);
        dlg.SetTitle(title);
        if (!string.IsNullOrEmpty(folder)) {
            IShellItemVFP si; var iid = IID_SI;
            int hr = SHCreateItemFromParsingName(folder, IntPtr.Zero, ref iid, out si);
            if (hr == 0 && si != null) {
                dlg.SetDefaultFolder(si);  // Fallback ohne Shell-Override
                dlg.SetFolder(si);         // erzwingt den Ordner immer
            }
        }
        return dlg;
    }

    private static string GetPath(IFileDialogVFP dlg) {
        IShellItemVFP item;
        if (dlg.GetResult(out item) != 0) return null;
        string path; item.GetDisplayName(unchecked((uint)0x80058000), out path);
        return path;
    }

    // Ordner-Auswahl
    public static string Pick(IntPtr owner, string title, string folder = null) {
        var dlg = MakeDialog(CLSID_FO, title, folder,
            0x00000020u | 0x00000040u); // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
        return dlg.Show(owner) == 0 ? GetPath(dlg) : null;
    }

    // Datei-Speichern-Dialog
    public static string SaveFile(IntPtr owner, string title, string folder,
                                  string defaultName, string defaultExt) {
        var dlg = MakeDialog(CLSID_FS, title, folder,
            0x00000002u); // FOS_OVERWRITEPROMPT
        if (!string.IsNullOrEmpty(defaultName)) dlg.SetFileName(defaultName);
        if (!string.IsNullOrEmpty(defaultExt))  dlg.SetDefaultExtension(defaultExt);
        return dlg.Show(owner) == 0 ? GetPath(dlg) : null;
    }

    // Datei-Oeffnen-Dialog
    public static string OpenFile(IntPtr owner, string title, string folder) {
        var dlg = MakeDialog(CLSID_FO, title, folder,
            0x00001000u); // FOS_FILEMUSTEXIST
        return dlg.Show(owner) == 0 ? GetPath(dlg) : null;
    }
}
'@
}

# Datei-Speichern/-Oeffnen via COM SetFolder() – erzwingt Startordner (ignoriert Shell-Merker)
# Eigene Klasse VistaFilePicker (kein Typ-Caching-Problem wie bei VistaFolderPicker)
if (-not ('VistaFilePicker' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IShellItemFP {
    void _s01(); void _s02();
    [PreserveSig] int GetDisplayName(uint sigdn,
        [MarshalAs(UnmanagedType.LPWStr)] out string name);
    void _s04(); void _s05();
}

[ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFileDialogFP {
    [PreserveSig] int Show(IntPtr hwnd);
    void _s02(); void _s03(); void _s04(); void _s05(); void _s06();
    [PreserveSig] int SetOptions(uint fos);
    [PreserveSig] int GetOptions(out uint pfos);
    [PreserveSig] int SetDefaultFolder(IShellItemFP psi);   // Slot 11
    [PreserveSig] int SetFolder(IShellItemFP psi);           // Slot 12 – erzwingt Ordner
    void _s11(); void _s12();
    [PreserveSig] int SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
    void _s14();
    [PreserveSig] int SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
    void _s16(); void _s17();
    [PreserveSig] int GetResult(out IShellItemFP ppsi);
    void _s19();
    [PreserveSig] int SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string ext);
    void _s21(); void _s22(); void _s23(); void _s24();
}

public static class VistaFilePicker {
    private static readonly Guid CLSID_FO = new Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7");
    private static readonly Guid CLSID_FS = new Guid("C0B4E2F3-BA21-4773-8DBA-335EC946EB8B");
    private static readonly Guid IID_SI   = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHCreateItemFromParsingName(
        string path, IntPtr pbc, ref Guid riid, out IShellItemFP ppv);

    private static IFileDialogFP Create(Guid clsid, string title, string folder, uint opts) {
        var dlg = (IFileDialogFP)Activator.CreateInstance(Type.GetTypeFromCLSID(clsid));
        uint cur; dlg.GetOptions(out cur);
        dlg.SetOptions(cur | opts);
        dlg.SetTitle(title);
        if (!string.IsNullOrEmpty(folder)) {
            IShellItemFP si; var iid = IID_SI;
            if (SHCreateItemFromParsingName(folder, IntPtr.Zero, ref iid, out si) == 0 && si != null) {
                dlg.SetDefaultFolder(si);
                dlg.SetFolder(si);
            }
        }
        return dlg;
    }

    private static string GetPath(IFileDialogFP dlg) {
        IShellItemFP item; if (dlg.GetResult(out item) != 0) return null;
        string p; item.GetDisplayName(unchecked((uint)0x80058000), out p); return p;
    }

    public static string Save(IntPtr owner, string title, string folder,
                              string defaultName, string defaultExt) {
        var dlg = Create(CLSID_FS, title, folder, 0x00000002u); // FOS_OVERWRITEPROMPT
        if (!string.IsNullOrEmpty(defaultName)) dlg.SetFileName(defaultName);
        if (!string.IsNullOrEmpty(defaultExt))  dlg.SetDefaultExtension(defaultExt);
        return dlg.Show(owner) == 0 ? GetPath(dlg) : null;
    }

    public static string Open(IntPtr owner, string title, string folder) {
        var dlg = Create(CLSID_FO, title, folder, 0x00001000u); // FOS_FILEMUSTEXIST
        return dlg.Show(owner) == 0 ? GetPath(dlg) : null;
    }
}
'@
}
#endregion

#region ── Globale Konstanten ──────────────────────────────────────────────────
$APP_VERSION   = '1.6.8.5'
$APP_COPYRIGHT = "schremar:ITServices $([char]169) 2026"
$APP_URL       = 'https://www.schremar.com/'

# Script-Ordner (PS Studio compatible) – wird auch von Settings/Profiles benoetigt
$script:appDir = if ($HostInvocation -and $HostInvocation.MyCommand.Path) {
                     Split-Path $HostInvocation.MyCommand.Path -Parent
                 } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$IniFile      = Join-Path $script:appDir 'backup.ini'
$SettingsFile = Join-Path $script:appDir 'settings.ini'
#endregion

#region ── Einstellungen (settings.ini) ────────────────────────────────────────
function Read-AppSettings {
    $s = @{ Language = 'en'; DefaultLogPathEnabled = 'false'; DefaultLogPath = '' }
    if (Test-Path $SettingsFile) {
        Get-Content $SettingsFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*(\w+)\s*=\s*(.*)$') {
                $k = $matches[1].Trim(); $v = $matches[2].Trim()
                if ($s.ContainsKey($k)) { $s[$k] = $v }
            }
        }
    }
    return $s
}
function Write-AppSettings ($lang, $defaultLogEnabled = 'false', $defaultLogPath = '') {
    @('[Settings]',
      "Language             = $lang",
      "DefaultLogPathEnabled = $defaultLogEnabled",
      "DefaultLogPath        = $defaultLogPath"
    ) | Set-Content -Path $SettingsFile -Encoding UTF8
}
#endregion

#region ── Sprachstrings ───────────────────────────────────────────────────────
$LANG_STRINGS = @{
    'en' = @{
        LangName        = 'English'
        SecPfade        = 'Paths';          SecOpt     = 'Options';     SecLog    = 'Output'
        BtnQuelle       = 'Source';          BtnZiel    = 'Destination'; BtnLogOrd = 'Log Folder'
        BtnQuelleFolder = 'Source: Folder'; BtnQuelleFile = 'Source: File'
        ChkVerify       = 'SHA256 checksum verification after backup'
        ChkDelete       = 'Delete destination folder BEFORE backup (Warning: irreversible!)'
        ChkDeleteFile   = 'Delete destination file BEFORE backup (Warning: irreversible!)'
        MsgDeleteFileWarn  = "WARNING: Destination file will be deleted irreversibly!`n`nFile: {0}`n`nContinue?"
        BtnStart        = '>  Start Backup'; BtnRunning = '...  Backup running'
        BtnReset        = 'Reset';          BtnSave    = 'Save Profile'; BtnLoad  = 'Load Profile'
        BtnQuit         = 'Quit'
        LblNoPath       = '(no path selected)'
        StatusReady     = 'Ready.';         StatusRunning = 'Robocopy running...'
        StatusDeleting  = 'Deleting destination...'; StatusVerify = 'Checksum verification running...'
        StatusDone      = 'Backup completed successfully.'
        StatusDelFail   = 'Delete error!';  StatusErrCode = 'Error! Robocopy code {0}'
        StatusSaved     = 'Profile saved: {0}'; StatusLoaded = 'Profile loaded: {0}'
        StatusPathsOk   = 'Paths: all reachable'
        StatusPathsWarn = 'Paths: {0} of 3 not reachable'
        StatusNoProf    = 'No profiles found.'
        MsgNoPaths      = 'Please select all three paths.'
        MsgNoSource     = "Source folder not found:`n{0}"
        MsgDeleteWarn   = "WARNING: Destination will be deleted irreversibly!`n`nPath: {0}`n`nContinue?"
        MsgDoneText     = "Backup completed!`nLog: {0}"
        MsgHint         = 'Hint';           MsgError   = 'Error'
        MsgDeleteTitle  = 'Safety check';   MsgDoneTitle = 'Done'
        DlgFolderSrc    = 'Select source folder'
        DlgFileSrc      = 'Select source file'
        DlgFolderDst    = 'Select destination folder'
        DlgFolderLog    = 'Select log folder'
        DlgSaveTitle    = 'Save profile';   DlgSavePrompt = 'Profile name (without .ini):'
        DlgSaveDefault  = 'backup_profile'
        DlgLoadTitle    = 'Load profile';   DlgLoadPrompt = 'Select profile:'; DlgLoadBtn = 'Load'
        DlgDelConfirm   = "Delete profile?`n`n{0}"; DlgDelTitle = 'Confirm'
        BtnOK           = 'OK';             BtnCancel  = 'Cancel';       BtnDelete  = 'Delete'
        DlgLangTitle    = 'Settings';           DlgLangPrompt = 'Select language:'
        DlgLangRestart  = "Language changed.`nPlease close and restart the application."
        DlgDefaultLogSection = 'Default LogFile Path'
        DlgDefaultLogEnabled = 'Always pre-fill log path on start and reset'
        DlgDefaultLogFolder  = 'Select default log folder'
        LogStarted      = '[{0}] Backup started'
        LogSrc          = '  Source : {0}'; LogDst = '  Dest   : {0}'; LogFile2 = '  Log    : {0}'
        LogDeleting     = 'Deleting destination folder...'
        LogDeleted      = 'Destination folder deleted.'
        LogDeleteErr    = 'Delete error: {0}'
        LogRcOK         = "`nRobocopy OK (Code {0})";  LogRcErr = "`nRobocopy error! (Code {0})"
        LogVerifyStart  = 'SHA256 verification starting...'
        LogMissing      = 'MISSING: {0}';   LogMismatch = 'MISMATCH: {0}'
        LogVerifyOK     = 'All files verified - OK'
        LogChecksumFile = 'Checksum log: {0}'
        LogVerifyWarn   = 'WARNING: {0} discrepancy/ies found!'
        LogVerifyDetail = 'Details: {0}'
        LogAllOK        = 'All files OK.';  LogDiscrep  = '{0} discrepancy/ies.'
        LogDone         = 'Backup completed.'
    }
    'de' = @{
        LangName        = 'Deutsch'
        SecPfade        = 'Pfade';          SecOpt     = 'Optionen';    SecLog    = 'Ausgabe'
        BtnQuelle       = 'Quelle';          BtnZiel    = 'Ziel Ordner'; BtnLogOrd = 'Pfad fuer LogFiles'
        BtnQuelleFolder = 'Quelle: Ordner'; BtnQuelleFile = 'Quelle: Datei'
        ChkVerify       = 'SHA256-Pruefsummen-Verifikation nach dem Backup'
        ChkDelete       = 'Ziel-Ordner VOR dem Backup loeschen (Achtung: unwiderruflich!)'
        ChkDeleteFile   = 'Ziel-Datei VOR dem Backup loeschen (Achtung: unwiderruflich!)'
        MsgDeleteFileWarn  = "ACHTUNG: Ziel-Datei wird unwiderruflich geloescht!`n`nDatei: {0}`n`nFortfahren?"
        BtnStart        = '>  Backup starten'; BtnRunning = '...  Backup laeuft'
        BtnReset        = 'Reset';          BtnSave    = 'Ini speichern'; BtnLoad = 'Ini laden'
        BtnQuit         = 'Beenden'
        LblNoPath       = '(kein Pfad gewaehlt)'
        StatusReady     = 'Bereit.';        StatusRunning = 'Robocopy laeuft...'
        StatusDeleting  = 'Ziel-Ordner wird geloescht...'; StatusVerify = 'Checksum-Verifikation laeuft...'
        StatusDone      = 'Backup erfolgreich abgeschlossen.'
        StatusDelFail   = 'Fehler beim Loeschen!'; StatusErrCode = 'Fehler! Robocopy Code {0}'
        StatusSaved     = 'Profil gespeichert: {0}'; StatusLoaded = 'Profil geladen: {0}'
        StatusPathsOk   = 'Pfade: alle erreichbar'
        StatusPathsWarn = 'Pfade: {0} von 3 nicht erreichbar'
        StatusNoProf    = 'Keine Profile vorhanden.'
        MsgNoPaths      = 'Bitte alle drei Pfade auswaehlen.'
        MsgNoSource     = "Quell-Ordner nicht gefunden:`n{0}"
        MsgDeleteWarn   = "ACHTUNG: Ziel-Ordner wird unwiderruflich geloescht!`n`nPfad: {0}`n`nFortfahren?"
        MsgDoneText     = "Backup abgeschlossen!`nLog: {0}"
        MsgHint         = 'Hinweis';        MsgError   = 'Fehler'
        MsgDeleteTitle  = 'Sicherheitsabfrage'; MsgDoneTitle = 'Fertig'
        DlgFolderSrc    = 'Quell-Ordner auswaehlen'
        DlgFileSrc      = 'Quelldatei auswaehlen'
        DlgFolderDst    = 'Ziel-Ordner auswaehlen'
        DlgFolderLog    = 'Log-Ordner auswaehlen'
        DlgSaveTitle    = 'Profil speichern'; DlgSavePrompt = 'Profil-Name (ohne .ini):'
        DlgSaveDefault  = 'backup_profil'
        DlgLoadTitle    = 'Profil laden';   DlgLoadPrompt = 'Profil auswaehlen:'; DlgLoadBtn = 'Laden'
        DlgDelConfirm   = "Profil loeschen?`n`n{0}"; DlgDelTitle = 'Bestaetigung'
        BtnOK           = 'OK';             BtnCancel  = 'Abbrechen';    BtnDelete  = 'Loeschen'
        DlgLangTitle    = 'Einstellungen';      DlgLangPrompt = 'Sprache auswaehlen:'
        DlgLangRestart  = "Sprache geaendert.`nBitte das Programm beenden und erneut starten."
        DlgDefaultLogSection = 'Standard LogFile-Pfad'
        DlgDefaultLogEnabled = 'Log-Pfad beim Start und Reset immer voreintragen'
        DlgDefaultLogFolder  = 'Standard Log-Ordner auswaehlen'
        LogStarted      = '[{0}] Backup gestartet'
        LogSrc          = '  Quelle : {0}'; LogDst = '  Ziel   : {0}'; LogFile2 = '  Log    : {0}'
        LogDeleting     = 'Ziel-Ordner wird geloescht...'
        LogDeleted      = 'Ziel-Ordner geloescht.'
        LogDeleteErr    = 'Fehler beim Loeschen: {0}'
        LogRcOK         = "`nRobocopy OK (Code {0})";  LogRcErr = "`nRobocopy Fehler! (Code {0})"
        LogVerifyStart  = 'SHA256-Verifikation startet...'
        LogMissing      = 'FEHLT: {0}';     LogMismatch = 'ABWEICHUNG: {0}'
        LogVerifyOK     = 'Alle Dateien verifiziert - OK'
        LogChecksumFile = 'Checksum-Log: {0}'
        LogVerifyWarn   = 'WARNUNG: {0} Abweichung(en) gefunden!'
        LogVerifyDetail = 'Details: {0}'
        LogAllOK        = 'Alle Dateien OK.'; LogDiscrep = '{0} Abweichung(en).'
        LogDone         = 'Backup abgeschlossen.'
    }
    'fr' = @{
        LangName        = 'Français'
        SecPfade        = 'Chemins';        SecOpt     = 'Options';     SecLog    = 'Sortie'
        BtnQuelle       = 'Source';          BtnZiel    = 'Dossier cible'; BtnLogOrd = 'Dossier journaux'
        BtnQuelleFolder = 'Source: Dossier'; BtnQuelleFile = 'Source: Fichier'
        ChkVerify       = 'Vérification SHA256 après la sauvegarde'
        ChkDelete       = 'Supprimer le dossier cible AVANT la sauvegarde (Attention: irréversible!)'
        ChkDeleteFile   = 'Supprimer le fichier cible AVANT la sauvegarde (Attention: irréversible!)'
        MsgDeleteFileWarn  = "ATTENTION: Le fichier cible sera supprimé irréversiblement!`n`nFichier: {0}`n`nContinuer?"
        BtnStart        = '>  Démarrer sauvegarde'; BtnRunning = '...  Sauvegarde en cours'
        BtnReset        = 'Réinitialiser'; BtnSave = 'Enreg. profil'; BtnLoad = 'Charger profil'
        BtnQuit         = 'Quitter'
        LblNoPath       = '(aucun chemin sélectionné)'
        StatusReady     = 'Prêt.';         StatusRunning = 'Robocopy en cours...'
        StatusDeleting  = 'Suppression du dossier cible...'; StatusVerify = 'Vérification en cours...'
        StatusDone      = 'Sauvegarde terminée avec succès.'
        StatusDelFail   = 'Erreur de suppression!'; StatusErrCode = 'Erreur! Code Robocopy {0}'
        StatusSaved     = 'Profil enregistré: {0}'; StatusLoaded = 'Profil chargé: {0}'
        StatusPathsOk   = 'Chemins: tous accessibles'
        StatusPathsWarn = 'Chemins: {0} sur 3 inaccessibles'
        StatusNoProf    = 'Aucun profil trouvé.'
        MsgNoPaths      = 'Veuillez sélectionner les trois chemins.'
        MsgNoSource     = "Dossier source introuvable:`n{0}"
        MsgDeleteWarn   = "ATTENTION: Le dossier cible sera supprimé irréversiblement!`n`nChemin: {0}`n`nContinuer?"
        MsgDoneText     = "Sauvegarde terminée!`nJournal: {0}"
        MsgHint         = 'Remarque';       MsgError   = 'Erreur'
        MsgDeleteTitle  = 'Confirmation de sécurité'; MsgDoneTitle = 'Terminé'
        DlgFolderSrc    = 'Sélectionner le dossier source'
        DlgFileSrc      = 'Sélectionner le fichier source'
        DlgFolderDst    = 'Sélectionner le dossier cible'
        DlgFolderLog    = 'Sélectionner le dossier journaux'
        DlgSaveTitle    = 'Enregistrer profil'; DlgSavePrompt = 'Nom du profil (sans .ini):'
        DlgSaveDefault  = 'profil_sauvegarde'
        DlgLoadTitle    = 'Charger profil';  DlgLoadPrompt = 'Sélectionner un profil:'; DlgLoadBtn = 'Charger'
        DlgDelConfirm   = "Supprimer le profil?`n`n{0}"; DlgDelTitle = 'Confirmation'
        BtnOK           = 'OK';             BtnCancel  = 'Annuler';      BtnDelete  = 'Supprimer'
        DlgLangTitle    = 'Paramètres';        DlgLangPrompt = 'Sélectionner la langue:'
        DlgLangRestart  = "Langue modifiée.`nVeuillez quitter et redémarrer l'application."
        DlgDefaultLogSection = 'Chemin journal par défaut'
        DlgDefaultLogEnabled = 'Toujours préremplir le chemin journal au démarrage'
        DlgDefaultLogFolder  = 'Sélectionner le dossier journal par défaut'
        LogStarted      = '[{0}] Sauvegarde démarrée'
        LogSrc          = '  Source : {0}'; LogDst = '  Cible  : {0}'; LogFile2 = '  Journal: {0}'
        LogDeleting     = 'Suppression du dossier cible...'
        LogDeleted      = 'Dossier cible supprimé.'
        LogDeleteErr    = 'Erreur lors de la suppression: {0}'
        LogRcOK         = "`nRobocopy OK (Code {0})"; LogRcErr = "`nErreur Robocopy! (Code {0})"
        LogVerifyStart  = 'Vérification SHA256 en cours...'
        LogMissing      = 'MANQUANT: {0}';  LogMismatch = 'DIVERGENCE: {0}'
        LogVerifyOK     = 'Tous les fichiers vérifiés - OK'
        LogChecksumFile = 'Journal de contrôle: {0}'
        LogVerifyWarn   = 'AVERTISSEMENT: {0} divergence(s) trouvée(s)!'
        LogVerifyDetail = 'Détails: {0}'
        LogAllOK        = 'Tous les fichiers OK.'; LogDiscrep = '{0} divergence(s).'
        LogDone         = 'Sauvegarde terminée.'
    }
    'es' = @{
        LangName        = 'Español'
        SecPfade        = 'Rutas';          SecOpt     = 'Opciones';    SecLog    = 'Salida'
        BtnQuelle       = 'Origen';          BtnZiel    = 'Carpeta destino'; BtnLogOrd = 'Carpeta registros'
        BtnQuelleFolder = 'Origen: Carpeta'; BtnQuelleFile = 'Origen: Archivo'
        ChkVerify       = 'Verificación SHA256 después de la copia de seguridad'
        ChkDelete       = 'Eliminar carpeta destino ANTES de la copia (Advertencia: irreversible!)'
        ChkDeleteFile   = 'Eliminar archivo destino ANTES de la copia (Advertencia: irreversible!)'
        MsgDeleteFileWarn  = "ATENCIÓN: El archivo destino se eliminará irreversiblemente!`n`nArchivo: {0}`n`n¿Continuar?"
        BtnStart        = '>  Iniciar copia'; BtnRunning = '...  Copia en curso'
        BtnReset        = 'Restablecer';    BtnSave    = 'Guardar perfil'; BtnLoad = 'Cargar perfil'
        BtnQuit         = 'Salir'
        LblNoPath       = '(ninguna ruta seleccionada)'
        StatusReady     = 'Listo.';         StatusRunning = 'Robocopy en ejecución...'
        StatusDeleting  = 'Eliminando carpeta destino...'; StatusVerify = 'Verificación en curso...'
        StatusDone      = 'Copia de seguridad completada.'
        StatusDelFail   = '¡Error al eliminar!'; StatusErrCode = '¡Error! Código Robocopy {0}'
        StatusSaved     = 'Perfil guardado: {0}'; StatusLoaded = 'Perfil cargado: {0}'
        StatusPathsOk   = 'Rutas: todas accesibles'
        StatusPathsWarn = 'Rutas: {0} de 3 no accesibles'
        StatusNoProf    = 'No hay perfiles.'
        MsgNoPaths      = 'Por favor seleccione las tres rutas.'
        MsgNoSource     = "Carpeta origen no encontrada:`n{0}"
        MsgDeleteWarn   = "ATENCIÓN: La carpeta destino se eliminará de forma irreversible!`n`nRuta: {0}`n`n¿Continuar?"
        MsgDoneText     = "¡Copia completada!`nRegistro: {0}"
        MsgHint         = 'Aviso';          MsgError   = 'Error'
        MsgDeleteTitle  = 'Confirmación de seguridad'; MsgDoneTitle = 'Completado'
        DlgFolderSrc    = 'Seleccionar carpeta origen'
        DlgFileSrc      = 'Seleccionar archivo fuente'
        DlgFolderDst    = 'Seleccionar carpeta destino'
        DlgFolderLog    = 'Seleccionar carpeta de registros'
        DlgSaveTitle    = 'Guardar perfil';  DlgSavePrompt = 'Nombre del perfil (sin .ini):'
        DlgSaveDefault  = 'perfil_copia'
        DlgLoadTitle    = 'Cargar perfil';   DlgLoadPrompt = 'Seleccionar perfil:'; DlgLoadBtn = 'Cargar'
        DlgDelConfirm   = "¿Eliminar perfil?`n`n{0}"; DlgDelTitle = 'Confirmación'
        BtnOK           = 'OK';             BtnCancel  = 'Cancelar';     BtnDelete  = 'Eliminar'
        DlgLangTitle    = 'Configuración';     DlgLangPrompt = 'Seleccionar idioma:'
        DlgLangRestart  = "Idioma cambiado.`nPor favor cierre y reinicie la aplicación."
        DlgDefaultLogSection = 'Ruta de registro predeterminada'
        DlgDefaultLogEnabled = 'Rellenar siempre la ruta de log al inicio y reset'
        DlgDefaultLogFolder  = 'Seleccionar carpeta de registro predeterminada'
        LogStarted      = '[{0}] Copia iniciada'
        LogSrc          = '  Origen : {0}'; LogDst = '  Destino: {0}'; LogFile2 = '  Registro: {0}'
        LogDeleting     = 'Eliminando carpeta destino...'
        LogDeleted      = 'Carpeta destino eliminada.'
        LogDeleteErr    = 'Error al eliminar: {0}'
        LogRcOK         = "`nRobocopy OK (Código {0})"; LogRcErr = "`n¡Error Robocopy! (Código {0})"
        LogVerifyStart  = 'Verificación SHA256 iniciada...'
        LogMissing      = 'FALTANTE: {0}';  LogMismatch = 'DISCREPANCIA: {0}'
        LogVerifyOK     = 'Todos los archivos verificados - OK'
        LogChecksumFile = 'Registro de suma: {0}'
        LogVerifyWarn   = 'ADVERTENCIA: {0} discrepancia(s) encontrada(s)!'
        LogVerifyDetail = 'Detalles: {0}'
        LogAllOK        = 'Todos los archivos OK.'; LogDiscrep = '{0} discrepancia(s).'
        LogDone         = 'Copia completada.'
    }
    'it' = @{
        LangName        = 'Italiano'
        SecPfade        = 'Percorsi';       SecOpt     = 'Opzioni';     SecLog    = 'Output'
        BtnQuelle       = 'Sorgente';           BtnZiel = 'Cartella destinazione'; BtnLogOrd = 'Cartella log'
        BtnQuelleFolder = 'Sorgente: Cartella'; BtnQuelleFile = 'Sorgente: File'
        ChkVerify       = 'Verifica SHA256 dopo il backup'
        ChkDelete       = 'Elimina cartella destinazione PRIMA del backup (Attenzione: irreversibile!)'
        ChkDeleteFile   = 'Elimina file destinazione PRIMA del backup (Attenzione: irreversibile!)'
        MsgDeleteFileWarn  = "ATTENZIONE: Il file destinazione verrà eliminato irreversibilmente!`n`nFile: {0}`n`nContinuare?"
        BtnStart        = '>  Avvia backup'; BtnRunning = '...  Backup in corso'
        BtnReset        = 'Reimposta';      BtnSave    = 'Salva profilo'; BtnLoad = 'Carica profilo'
        BtnQuit         = 'Esci'
        LblNoPath       = '(nessun percorso selezionato)'
        StatusReady     = 'Pronto.';        StatusRunning = 'Robocopy in esecuzione...'
        StatusDeleting  = 'Eliminazione cartella destinazione...'; StatusVerify = 'Verifica in corso...'
        StatusDone      = 'Backup completato con successo.'
        StatusDelFail   = 'Errore durante eliminazione!'; StatusErrCode = 'Errore! Codice Robocopy {0}'
        StatusSaved     = 'Profilo salvato: {0}'; StatusLoaded = 'Profilo caricato: {0}'
        StatusPathsOk   = 'Percorsi: tutti raggiungibili'
        StatusPathsWarn = 'Percorsi: {0} su 3 non raggiungibili'
        StatusNoProf    = 'Nessun profilo trovato.'
        MsgNoPaths      = 'Selezionare tutti e tre i percorsi.'
        MsgNoSource     = "Cartella sorgente non trovata:`n{0}"
        MsgDeleteWarn   = "ATTENZIONE: La cartella destinazione verrà eliminata irreversibilmente!`n`nPercorso: {0}`n`nContinuare?"
        MsgDoneText     = "Backup completato!`nLog: {0}"
        MsgHint         = 'Avviso';         MsgError   = 'Errore'
        MsgDeleteTitle  = 'Conferma di sicurezza'; MsgDoneTitle = 'Completato'
        DlgFolderSrc    = 'Seleziona cartella sorgente'
        DlgFileSrc      = 'Seleziona file sorgente'
        DlgFolderDst    = 'Seleziona cartella destinazione'
        DlgFolderLog    = 'Seleziona cartella log'
        DlgSaveTitle    = 'Salva profilo';   DlgSavePrompt = 'Nome profilo (senza .ini):'
        DlgSaveDefault  = 'profilo_backup'
        DlgLoadTitle    = 'Carica profilo';  DlgLoadPrompt = 'Seleziona profilo:'; DlgLoadBtn = 'Carica'
        DlgDelConfirm   = "Eliminare il profilo?`n`n{0}"; DlgDelTitle = 'Conferma'
        BtnOK           = 'OK';             BtnCancel  = 'Annulla';      BtnDelete  = 'Elimina'
        DlgLangTitle    = 'Impostazioni';      DlgLangPrompt = 'Seleziona lingua:'
        DlgLangRestart  = "Lingua modificata.`nChiudere e riavviare l'applicazione."
        DlgDefaultLogSection = 'Percorso log predefinito'
        DlgDefaultLogEnabled = 'Precompila sempre il percorso log allavvio e reset'
        DlgDefaultLogFolder  = 'Seleziona cartella log predefinita'
        LogStarted      = '[{0}] Backup avviato'
        LogSrc          = '  Sorgente: {0}'; LogDst = '  Dest.   : {0}'; LogFile2 = '  Log     : {0}'
        LogDeleting     = 'Eliminazione cartella destinazione...'
        LogDeleted      = 'Cartella destinazione eliminata.'
        LogDeleteErr    = "Errore durante l'eliminazione: {0}"
        LogRcOK         = "`nRobocopy OK (Codice {0})"; LogRcErr = "`nErrore Robocopy! (Codice {0})"
        LogVerifyStart  = 'Verifica SHA256 avviata...'
        LogMissing      = 'MANCANTE: {0}';  LogMismatch = 'DISCREPANZA: {0}'
        LogVerifyOK     = 'Tutti i file verificati - OK'
        LogChecksumFile = 'Log di checksum: {0}'
        LogVerifyWarn   = "ATTENZIONE: {0} discrepanza/e trovata/e!"
        LogVerifyDetail = 'Dettagli: {0}'
        LogAllOK        = 'Tutti i file OK.'; LogDiscrep = '{0} discrepanza/e.'
        LogDone         = 'Backup completato.'
    }
}

# Aktive Sprache laden
$_s    = Read-AppSettings
$_lang = if ($LANG_STRINGS.ContainsKey($_s.Language)) { $_s.Language } else { 'en' }
$T     = $LANG_STRINGS[$_lang]          # $T = aktive Uebersetzungstabelle
$CURRENT_LANG = $_lang
# Default LogFile-Pfad Einstellungen
$script:defaultLogEnabled = ($_s.DefaultLogPathEnabled -eq 'true')
$script:defaultLogPath    = $_s.DefaultLogPath
#endregion

#region ── Farben und Schriften ────────────────────────────────────────────────
function New-Color ($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function New-Font  ($name, $size, $style = 'Regular') {
    New-Object System.Drawing.Font($name, $size, [System.Drawing.FontStyle]::$style)
}

$C_BG     = New-Color '#2F4F4F'
$C_BG2    = New-Color '#2b2f55'
$C_BG3    = New-Color '#263d3d'    # etwas dunkler fuer Sektions-Header
$C_HDR    = New-Color '#6e56b3'
$C_ACCENT = New-Color '#8b5cf6'
$C_ACCH   = New-Color '#7c3aed'
$C_OK     = New-Color '#4ade80'
$C_ERR    = New-Color '#f87171'
$C_WARN   = New-Color '#fbbf24'
$C_DOT_OK   = New-Color '#22c55e'   # grüner Punkt  – Pfad erreichbar
$C_DOT_WARN = New-Color '#f97316'   # oranger Punkt – Pfad nicht erreichbar
$C_FG     = New-Color '#f0f4ff'
$C_FG2    = New-Color '#a5b4fc'
$C_LOGBG  = New-Color '#13152b'
$C_FOOT   = New-Color '#1a1a2e'
$C_DIMTXT = New-Color '#64748b'
$C_SEP    = New-Color '#4a6060'    # Trennlinie Sektionen

$F_UI   = New-Font 'Segoe UI' 11
$F_BOLD = New-Font 'Segoe UI' 11 'Bold'
$F_SEC  = New-Font 'Segoe UI' 10 'Bold'
$F_BIG  = New-Font 'Segoe UI' 14 'Bold'
$F_MONO = New-Font 'Consolas'  10
$F_SM   = New-Font 'Segoe UI'   9

$ANC_TL  = [System.Windows.Forms.AnchorStyles]::Top  -bor [System.Windows.Forms.AnchorStyles]::Left
$ANC_TR  = [System.Windows.Forms.AnchorStyles]::Top  -bor [System.Windows.Forms.AnchorStyles]::Right
$ANC_TLR = [System.Windows.Forms.AnchorStyles]::Top  -bor [System.Windows.Forms.AnchorStyles]::Left `
           -bor [System.Windows.Forms.AnchorStyles]::Right
#endregion

#region ── INI ─────────────────────────────────────────────────────────────────
function Read-Ini {
    $cfg = @{ Source = ''; Destination = ''; LogFolder = ''; SourceMode = 'folder' }
    if (Test-Path $IniFile) {
        Get-Content $IniFile -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*(\w+)\s*=\s*(.*)$') {
                $k = $matches[1].Trim(); $v = $matches[2].Trim()
                if ($cfg.ContainsKey($k)) { $cfg[$k] = $v }
            }
        }
    }
    return $cfg
}
function Write-Ini ($src, $dst, $log, $sourceMode = 'folder') {
    @("[Paths]", "Source = $src", "Destination = $dst", "LogFolder = $log", "SourceMode = $sourceMode") |
        Set-Content -Path $IniFile -Encoding UTF8
}
#endregion

#region ── SHA256 ──────────────────────────────────────────────────────────────
function Get-SHA256 ($path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs  = [System.IO.File]::OpenRead($path)
    try   { [BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-' }
    finally { $fs.Close(); $sha.Dispose() }
}
#endregion

#region ── ScriptForm Designer ─────────────────────────────────────────────────
function GenerateForm {

    # Script-Ordner aus script:-Scope (wurde bereits vor GenerateForm ermittelt)
    $appDir = $script:appDir

    #region ── Form-Objekte (Deklaration) ─────────────────────────────────────
    $formMain        = New-Object 'System.Windows.Forms.Form'
    $panelHeader     = New-Object 'System.Windows.Forms.Panel'
    $labelTitle      = New-Object 'System.Windows.Forms.Label'
    $panelFooter     = New-Object 'System.Windows.Forms.Panel'
    $labelVersion    = New-Object 'System.Windows.Forms.Label'
    $linkCopyright   = New-Object 'System.Windows.Forms.LinkLabel'
    $panelMain       = New-Object 'System.Windows.Forms.Panel'
    # Pfade-Sektion (Panel-basiert, kein GroupBox)
    $secPfade        = New-Object 'System.Windows.Forms.Panel'
    $secPfadeBar     = New-Object 'System.Windows.Forms.Panel'
    $secPfadeTitle   = New-Object 'System.Windows.Forms.Label'
    $secPfadeContent = New-Object 'System.Windows.Forms.Panel'
    $btnQuelle       = New-Object 'System.Windows.Forms.Button'
    $btnQuelleMode   = New-Object 'System.Windows.Forms.Button'
    $lblQuelle       = New-Object 'System.Windows.Forms.Label'
    $lblDotQuelle    = New-Object 'System.Windows.Forms.Label'
    $script:quelleMode = 'folder'
    $btnZiel         = New-Object 'System.Windows.Forms.Button'
    $lblZiel         = New-Object 'System.Windows.Forms.Label'
    $lblDotZiel      = New-Object 'System.Windows.Forms.Label'
    $btnLogOrdner    = New-Object 'System.Windows.Forms.Button'
    $lblLog          = New-Object 'System.Windows.Forms.Label'
    $lblDotLog       = New-Object 'System.Windows.Forms.Label'
    # Optionen-Sektion (Panel-basiert, kein GroupBox)
    $secOpt          = New-Object 'System.Windows.Forms.Panel'
    $secOptBar       = New-Object 'System.Windows.Forms.Panel'
    $secOptTitle     = New-Object 'System.Windows.Forms.Label'
    $secOptContent   = New-Object 'System.Windows.Forms.Panel'
    $chkVerify       = New-Object 'System.Windows.Forms.CheckBox'
    $chkDelete       = New-Object 'System.Windows.Forms.CheckBox'
    $chkDeleteFile   = New-Object 'System.Windows.Forms.CheckBox'
    # Buttons / Status / Log
    $panelButtons        = New-Object 'System.Windows.Forms.Panel'
    $btnStart            = New-Object 'System.Windows.Forms.Button'
    $btnClearLog         = New-Object 'System.Windows.Forms.Button'
    $btnSaveIni          = New-Object 'System.Windows.Forms.Button'
    $btnLoadIni          = New-Object 'System.Windows.Forms.Button'
    $btnBeendenWrapper   = New-Object 'System.Windows.Forms.Panel'
    $btnBeenden          = New-Object 'System.Windows.Forms.Button'
    $btnLang             = New-Object 'System.Windows.Forms.Button'
    $timerRobocopy       = New-Object 'System.Windows.Forms.Timer'
    $progressBar     = New-Object 'System.Windows.Forms.ProgressBar'
    $panelStatus     = New-Object 'System.Windows.Forms.Panel'
    $lblStatus       = New-Object 'System.Windows.Forms.Label'
    $lblStatusPaths  = New-Object 'System.Windows.Forms.Label'
    # Ausgabe-Sektion (Panel-basiert, kein GroupBox)
    $secLog          = New-Object 'System.Windows.Forms.Panel'
    $secLogBar       = New-Object 'System.Windows.Forms.Panel'
    $secLogTitle     = New-Object 'System.Windows.Forms.Label'
    $rtbLog          = New-Object 'System.Windows.Forms.RichTextBox'
    #endregion

    #region ── Interne Hilfsfunktionen ────────────────────────────────────────
    function Set-PathLabel ($lbl, $path) {
        $lbl.Text      = $path
        $lbl.ForeColor = [System.Drawing.Color]::White
        $lbl.Tag       = $path
    }

    function Write-LogLine ($text, $color) {
        if (-not $color) { $color = $C_FG }
        $rtbLog.SelectionStart  = $rtbLog.TextLength
        $rtbLog.SelectionLength = 0
        $rtbLog.SelectionColor  = $color
        $rtbLog.AppendText("$text`n")
        $rtbLog.ScrollToCaret()
    }

    function Set-Status ($text) { $lblStatus.Text = $text }

    function Show-OpenFileDialog ($initialPath = '') {
        $dlg = New-Object 'System.Windows.Forms.OpenFileDialog'
        $dlg.Title  = $T.DlgFileSrc
        $dlg.Filter = '*.*|*.*'
        if ($initialPath) {
            $dir = if ([System.IO.File]::Exists($initialPath)) {
                [System.IO.Path]::GetDirectoryName($initialPath)
            } elseif ([System.IO.Directory]::Exists($initialPath)) { $initialPath }
            if ($dir) { $dlg.InitialDirectory = $dir }
        }
        if ($dlg.ShowDialog($formMain) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dlg.FileName
        }
        return $null
    }

    function Show-FolderDialog ($title, $initialPath = '') {
        $path = [VistaFolderPicker]::Pick($formMain.Handle, $title, $initialPath)
        return $path
    }

    $defaultDir = [System.Environment]::GetFolderPath('MyDocuments')

    # Hilfsfunktion: DPI-skalierte Point/Size via GetDpiForMonitor (funktioniert ohne .exe.config)
    function New-Pt ($x, $y) {
        $s = [MonitorDpi]::Get($formMain.Handle) / 96.0
        New-Object 'System.Drawing.Point'([int]($x*$s), [int]($y*$s))
    }
    function New-Sz ($w, $h) {
        $s = [MonitorDpi]::Get($formMain.Handle) / 96.0
        New-Object 'System.Drawing.Size'([int]($w*$s), [int]($h*$s))
    }

    # Einfacher Eingabe-Dialog (fuer Profil-Name beim Speichern)
    # $prefix: optionaler fester Präfix (z.B. 'File_' / 'Folder_') – nicht editierbar
    function Show-InputBox ($prompt, $default, $prefix = '') {
        $f = New-Object 'System.Windows.Forms.Form'
        $f.Text            = $T.DlgSaveTitle
        $f.ClientSize      = New-Sz 380 145
        $f.StartPosition   = 'CenterParent'
        $f.FormBorderStyle = 'FixedDialog'
        $f.MaximizeBox     = $false; $f.MinimizeBox = $false
        $f.BackColor = $C_BG; $f.ForeColor = $C_FG; $f.Font = $F_UI
        $f.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None

        $lbl = New-Object 'System.Windows.Forms.Label'
        $lbl.Text     = $prompt
        $lbl.Location = New-Pt 12 12
        $lbl.Size     = New-Sz 356 20
        $lbl.ForeColor = $C_FG2; $lbl.BackColor = $C_BG

        # Fester Präfix-Label (nicht editierbar) wenn Präfix angegeben
        $tbX = 12; $tbW = 356
        if ($prefix) {
            $lblPrefix = New-Object 'System.Windows.Forms.Label'
            $lblPrefix.Text        = $prefix
            $lblPrefix.Location    = New-Pt 12 38
            $lblPrefix.Size        = New-Sz 72 26
            $lblPrefix.BackColor   = $C_BG3
            $lblPrefix.ForeColor   = $C_FG2
            $lblPrefix.BorderStyle = 'FixedSingle'
            $lblPrefix.TextAlign   = 'MiddleCenter'
            $lblPrefix.Font        = $F_SEC
            $f.Controls.Add($lblPrefix)
            $tbX = 86; $tbW = 282
        }

        $tb = New-Object 'System.Windows.Forms.TextBox'
        $tb.Text        = $default
        $tb.Location    = New-Pt $tbX 38
        $tb.Size        = New-Sz $tbW 26
        $tb.BackColor   = $C_BG2; $tb.ForeColor = $C_FG
        $tb.BorderStyle = 'FixedSingle'

        $btnOK = New-Object 'System.Windows.Forms.Button'
        $btnOK.Text          = $T.BtnOK
        $btnOK.Location      = New-Pt 188 100
        $btnOK.Size          = New-Sz 82 32
        $btnOK.DialogResult  = 'OK'
        $btnOK.FlatStyle     = 'Flat'
        $btnOK.FlatAppearance.BorderSize = 0
        $btnOK.BackColor = $C_ACCENT; $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.Font = $F_BOLD

        $btnCancel = New-Object 'System.Windows.Forms.Button'
        $btnCancel.Text         = $T.BtnCancel
        $btnCancel.Location     = New-Pt 278 100
        $btnCancel.Size         = New-Sz 90 32
        $btnCancel.DialogResult = 'Cancel'
        $btnCancel.FlatStyle    = 'Flat'
        $btnCancel.FlatAppearance.BorderColor = $C_SEP
        $btnCancel.FlatAppearance.BorderSize  = 1
        $btnCancel.BackColor = $C_BG2; $btnCancel.ForeColor = $C_FG2

        $f.AcceptButton = $btnOK; $f.CancelButton = $btnCancel
        $f.Controls.AddRange(@($lbl, $tb, $btnOK, $btnCancel))
        $tb.Select(); $tb.SelectAll()
        if ($f.ShowDialog($formMain) -eq 'OK') { return $prefix + $tb.Text.Trim() }
        return $null
    }

    # Profil-Auswahl-Dialog (ListBox mit vorhandenen INI-Dateien)
    function Show-ProfileList ($profilesDir) {
        $files = @(Get-ChildItem $profilesDir -Filter '*.ini' -ErrorAction SilentlyContinue |
                   Sort-Object Name | Select-Object -ExpandProperty Name)
        if ($files.Count -eq 0) { Set-Status $T.StatusNoProf; return $null }

        $f = New-Object 'System.Windows.Forms.Form'
        $f.Text            = $T.DlgLoadTitle
        $f.ClientSize      = New-Sz 420 300
        $f.StartPosition   = 'CenterParent'
        $f.FormBorderStyle = 'FixedDialog'
        $f.MaximizeBox     = $false; $f.MinimizeBox = $false
        $f.BackColor = $C_BG; $f.ForeColor = $C_FG; $f.Font = $F_UI
        $f.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None

        $lbl = New-Object 'System.Windows.Forms.Label'
        $lbl.Text     = $T.DlgLoadPrompt
        $lbl.Location = New-Pt 12 12
        $lbl.Size     = New-Sz 396 20
        $lbl.ForeColor = $C_FG2; $lbl.BackColor = $C_BG

        $lb = New-Object 'System.Windows.Forms.ListBox'
        $lb.Location    = New-Pt 12 36
        $lb.Size        = New-Sz 396 210
        $lb.BackColor   = $C_BG2; $lb.ForeColor = $C_FG
        $lb.BorderStyle = 'FixedSingle'
        $lb.Font        = $F_UI
        $files | ForEach-Object { $lb.Items.Add($_) | Out-Null }
        $lb.SelectedIndex = 0

        $btnOK = New-Object 'System.Windows.Forms.Button'
        $btnOK.Text         = $T.DlgLoadBtn
        $btnOK.Location     = New-Pt 210 258
        $btnOK.Size         = New-Sz 96 32
        $btnOK.DialogResult = 'OK'
        $btnOK.FlatStyle    = 'Flat'
        $btnOK.FlatAppearance.BorderSize = 0
        $btnOK.BackColor = $C_ACCENT; $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.Font = $F_BOLD

        $btnDelete = New-Object 'System.Windows.Forms.Button'
        $btnDelete.Text      = $T.BtnDelete
        $btnDelete.Location  = New-Pt 12 258
        $btnDelete.Size      = New-Sz 100 32
        $btnDelete.FlatStyle = 'Flat'
        $btnDelete.FlatAppearance.BorderColor = $C_ERR
        $btnDelete.FlatAppearance.BorderSize  = 1
        $btnDelete.BackColor = $C_BG2; $btnDelete.ForeColor = $C_ERR
        $btnDelete.add_Click({
            $sel = $lb.SelectedItem
            if (-not $sel) { return }
            $ans = [System.Windows.Forms.MessageBox]::Show(
                ($T.DlgDelConfirm -f $sel), $T.DlgDelTitle, 'YesNo', 'Warning')
            if ($ans -ne 'Yes') { return }
            $path = Join-Path $profilesDir $sel
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
            $idx = $lb.SelectedIndex
            $lb.Items.Remove($sel)
            if ($lb.Items.Count -eq 0) { $f.DialogResult = 'Cancel'; $f.Close(); return }
            $lb.SelectedIndex = [Math]::Min($idx, $lb.Items.Count - 1)
        })

        $btnCancel = New-Object 'System.Windows.Forms.Button'
        $btnCancel.Text         = $T.BtnCancel
        $btnCancel.Location     = New-Pt 314 258
        $btnCancel.Size         = New-Sz 94 32
        $btnCancel.DialogResult = 'Cancel'
        $btnCancel.FlatStyle    = 'Flat'
        $btnCancel.FlatAppearance.BorderColor = $C_SEP
        $btnCancel.FlatAppearance.BorderSize  = 1
        $btnCancel.BackColor = $C_BG2; $btnCancel.ForeColor = $C_FG2

        $lb.add_DoubleClick({ $f.DialogResult = 'OK'; $f.Close() })
        $f.AcceptButton = $btnOK; $f.CancelButton = $btnCancel
        $f.Controls.AddRange(@($lbl, $lb, $btnOK, $btnDelete, $btnCancel))

        if ($f.ShowDialog($formMain) -eq 'OK' -and $lb.SelectedItem) {
            return Join-Path $profilesDir $lb.SelectedItem
        }
        return $null
    }

    # Sprach-Auswahl-Dialog
    function Show-LangDialog {
        $f = New-Object 'System.Windows.Forms.Form'
        $f.Text            = $T.DlgLangTitle
        $f.ClientSize      = New-Sz 420 370
        $f.StartPosition   = 'CenterParent'
        $f.FormBorderStyle = 'FixedDialog'
        $f.MaximizeBox     = $false; $f.MinimizeBox = $false
        $f.BackColor = $C_BG; $f.ForeColor = $C_FG; $f.Font = $F_UI
        $f.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None

        # ── Sprache ──────────────────────────────────────────────────────
        $lbl = New-Object 'System.Windows.Forms.Label'
        $lbl.Text      = $T.DlgLangPrompt
        $lbl.Location  = New-Pt 12 12
        $lbl.Size      = New-Sz 396 20
        $lbl.ForeColor = $C_FG2; $lbl.BackColor = $C_BG

        $langs = [ordered]@{ 'en'='🇬🇧  English'; 'de'='🇩🇪  Deutsch'; 'fr'='🇫🇷  Français'
                              'es'='🇪🇸  Español';  'it'='🇮🇹  Italiano' }
        $rb = @{}; $y = 38
        foreach ($code in $langs.Keys) {
            $r = New-Object 'System.Windows.Forms.RadioButton'
            $r.Text      = $langs[$code]
            $r.Tag       = $code
            $r.Location  = New-Pt 16 $y
            $r.Size      = New-Sz 390 24
            $r.ForeColor = $C_FG; $r.BackColor = $C_BG
            $r.Checked   = ($code -eq $CURRENT_LANG)
            $f.Controls.Add($r)
            $rb[$code] = $r
            $y += 28
        }

        # ── Trennlinie ───────────────────────────────────────────────────
        $sep = New-Object 'System.Windows.Forms.Panel'
        $sep.Location  = New-Pt 12 185
        $sep.Size      = New-Sz 396 1
        $sep.BackColor = $C_SEP

        # ── Default LogFile-Pfad Abschnitt ────────────────────────────────
        $lblSection = New-Object 'System.Windows.Forms.Label'
        $lblSection.Text      = $T.DlgDefaultLogSection
        $lblSection.Location  = New-Pt 12 196
        $lblSection.Size      = New-Sz 396 20
        $lblSection.Font      = $F_SEC
        $lblSection.ForeColor = $C_FG2; $lblSection.BackColor = $C_BG

        $chkDefault = New-Object 'System.Windows.Forms.CheckBox'
        $chkDefault.Text      = $T.DlgDefaultLogEnabled
        $chkDefault.Location  = New-Pt 12 222
        $chkDefault.Size      = New-Sz 396 24
        $chkDefault.ForeColor = $C_FG; $chkDefault.BackColor = $C_BG
        $chkDefault.Checked   = $script:defaultLogEnabled

        $tbDefaultPath = New-Object 'System.Windows.Forms.TextBox'
        $tbDefaultPath.Text        = $script:defaultLogPath
        $tbDefaultPath.Location    = New-Pt 12 256
        $tbDefaultPath.Size        = New-Sz 310 26
        $tbDefaultPath.BackColor   = $C_BG2; $tbDefaultPath.ForeColor = $C_FG
        $tbDefaultPath.BorderStyle = 'FixedSingle'
        $tbDefaultPath.Enabled     = $script:defaultLogEnabled

        $btnBrowse = New-Object 'System.Windows.Forms.Button'
        $btnBrowse.Text      = '...'
        $btnBrowse.Location  = New-Pt 330 254
        $btnBrowse.Size      = New-Sz 78 30
        $btnBrowse.FlatStyle = 'Flat'
        $btnBrowse.FlatAppearance.BorderColor = $C_SEP
        $btnBrowse.FlatAppearance.BorderSize  = 1
        $btnBrowse.BackColor = $C_BG2; $btnBrowse.ForeColor = $C_FG
        $btnBrowse.Enabled   = $script:defaultLogEnabled
        $btnBrowse.Cursor    = [System.Windows.Forms.Cursors]::Hand

        # Aktivierung/Deaktivierung bei Checkbox-Änderung
        $chkDefault.add_CheckedChanged({
            $tbDefaultPath.Enabled = $chkDefault.Checked
            $btnBrowse.Enabled     = $chkDefault.Checked
        })
        $btnBrowse.add_Click({
            $p = Show-FolderDialog $T.DlgDefaultLogFolder $tbDefaultPath.Text
            if ($p) { $tbDefaultPath.Text = $p }
        })

        # ── OK / Abbrechen ────────────────────────────────────────────────
        $btnOK = New-Object 'System.Windows.Forms.Button'
        $btnOK.Text         = $T.BtnOK
        $btnOK.Location     = New-Pt 210 326
        $btnOK.Size         = New-Sz 96 32
        $btnOK.DialogResult = 'OK'
        $btnOK.FlatStyle    = 'Flat'
        $btnOK.FlatAppearance.BorderSize = 0
        $btnOK.BackColor = $C_ACCENT; $btnOK.ForeColor = [System.Drawing.Color]::White
        $btnOK.Font = $F_BOLD

        $btnCancel = New-Object 'System.Windows.Forms.Button'
        $btnCancel.Text         = $T.BtnCancel
        $btnCancel.Location     = New-Pt 314 326
        $btnCancel.Size         = New-Sz 94 32
        $btnCancel.DialogResult = 'Cancel'
        $btnCancel.FlatStyle    = 'Flat'
        $btnCancel.FlatAppearance.BorderColor = $C_SEP
        $btnCancel.FlatAppearance.BorderSize  = 1
        $btnCancel.BackColor = $C_BG2; $btnCancel.ForeColor = $C_FG2

        $f.AcceptButton = $btnOK; $f.CancelButton = $btnCancel
        $f.Controls.AddRange(@($lbl, $sep, $lblSection, $chkDefault,
                                $tbDefaultPath, $btnBrowse, $btnOK, $btnCancel))

        if ($f.ShowDialog($formMain) -ne 'OK') { return }

        # ── Einstellungen speichern ───────────────────────────────────────
        $newEnabled = $chkDefault.Checked
        $newPath    = $tbDefaultPath.Text.Trim()
        $script:defaultLogEnabled = $newEnabled
        $script:defaultLogPath    = $newPath

        $sel = ($rb.Values | Where-Object { $_.Checked } | Select-Object -First 1)
        $newLang = if ($sel) { $sel.Tag } else { $CURRENT_LANG }

        Write-AppSettings $newLang ($newEnabled.ToString().ToLower()) $newPath

        # Log-Pfad sofort anwenden wenn aktiviert und noch nicht gesetzt
        if ($newEnabled -and $newPath -and -not $lblLog.Tag) {
            Set-PathLabel $lblLog $newPath
            Write-Ini $lblQuelle.Tag $lblZiel.Tag $lblLog.Tag $script:quelleMode
            Update-StartButton; Update-PathStatus
        }

        # Sprachaenderung → Neustart erforderlich
        if ($sel -and $sel.Tag -ne $CURRENT_LANG) {
            [System.Windows.Forms.MessageBox]::Show(
                $T.DlgLangRestart, $T.DlgLangTitle, 'OK', 'Information') | Out-Null
        }
    }

    function Get-RcArgs ($job) {
        if ($job.FileMode) {
            # Einzeldatei: Elternordner als Quelle, Dateiname als Filter, kein /MIR
            $srcDir  = [System.IO.Path]::GetDirectoryName($job.Src)
            $srcFile = [System.IO.Path]::GetFileName($job.Src)
            return @("`"$srcDir`"", "`"$($job.Dst)`"", "`"$srcFile`"",
                     '/R:1', '/W:1', "/LOG:`"$($job.LogFile)`"")
        } else {
            return @("`"$($job.Src)`"", "`"$($job.Dst)`"",
                     '/MIR', '/R:1', '/W:1', "/LOG:`"$($job.LogFile)`"")
        }
    }

    function Set-QuelleMode ($mode) {
        $script:quelleMode  = $mode
        $btnQuelle.Text     = if ($mode -eq 'file') { $T.BtnQuelleFile } else { $T.BtnQuelleFolder }
        $btnQuelleMode.Text = if ($mode -eq 'file') {
            [System.Char]::ConvertFromUtf32(0x1F4C4)   # 📄
        } else {
            [System.Char]::ConvertFromUtf32(0x1F4C1)   # 📁
        }
        # chkDeleteFile nur im Datei-Modus aktiv
        $isFile = ($mode -eq 'file')
        $chkDeleteFile.Enabled = $isFile
        if (-not $chkDeleteFile.Enabled) { $chkDeleteFile.Checked = $false }
    }

    function Update-StartButton {
        $ok = ($lblQuelle.Tag -and $lblZiel.Tag -and $lblLog.Tag)
        $btnStart.Enabled   = $ok
        $btnStart.BackColor = if ($ok) { $C_ACCENT } else { $C_BG2 }
        $btnStart.ForeColor = if ($ok) { [System.Drawing.Color]::White } else { $C_FG2 }
    }

    function Test-FolderWritable ($folderPath) {
        # Prüft ob ein Ordner wirklich zugänglich ist (z.B. entschlüsselt),
        # indem eine kleine Testdatei geschrieben und sofort wieder gelöscht wird.
        try {
            $testFile = Join-Path $folderPath ('.eri_test_' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
            [System.IO.File]::WriteAllText($testFile, 'ERI-write-test')
            [System.IO.File]::Delete($testFile)
            return $true
        } catch {
            return $false
        }
    }

    function Update-PathStatus {
        $entries = @(
            @{ Lbl = $lblQuelle; Dot = $lblDotQuelle; WriteTest = $true  }
            @{ Lbl = $lblZiel;   Dot = $lblDotZiel;   WriteTest = $false }
            @{ Lbl = $lblLog;    Dot = $lblDotLog;     WriteTest = $false }
        )
        $notReachable = 0
        $withPath     = 0
        foreach ($e in $entries) {
            if ($e.Lbl.Tag) {
                $withPath++
                $pathOk = Test-Path $e.Lbl.Tag
                # Zusätzliche Schreibzugriff-Prüfung nur für Quelle im Ordner-Modus
                if ($pathOk -and $e.WriteTest -and $script:quelleMode -eq 'folder') {
                    $pathOk = Test-FolderWritable $e.Lbl.Tag
                }
                if ($pathOk) {
                    $e.Dot.ForeColor = $C_DOT_OK
                } else {
                    $e.Dot.ForeColor = $C_DOT_WARN
                    $notReachable++
                }
            } else {
                $e.Dot.ForeColor = $C_BG   # unsichtbar
            }
        }
        # Start-Button: nur aktiv wenn alle 3 Pfade gesetzt UND alle erreichbar
        $allSet = ($lblQuelle.Tag -and $lblZiel.Tag -and $lblLog.Tag)
        $ok     = ($allSet -and $notReachable -eq 0)
        $btnStart.Enabled   = $ok
        $btnStart.BackColor = if ($ok) { $C_ACCENT } else { $C_BG2 }
        $btnStart.ForeColor = if ($ok) { [System.Drawing.Color]::White } else { $C_FG2 }

        if ($withPath -eq 0 -or (-not $allSet -and $notReachable -eq 0)) {
            $lblStatusPaths.Text      = ''
            $lblStatusPaths.ForeColor = $C_FG2
        } elseif ($allSet -and $notReachable -eq 0) {
            $lblStatusPaths.Text      = $T.StatusPathsOk
            $lblStatusPaths.ForeColor = $C_DOT_OK
        } else {
            $lblStatusPaths.Text      = $T.StatusPathsWarn -f $notReachable
            $lblStatusPaths.ForeColor = $C_DOT_WARN
        }
    }

    # Hilfsfunktion: Sektions-Header aufbauen (Akzentbalken + Titel)
    # Uebergabe: Sektion-Panel, Bar-Panel, Title-Label, Titeltext
    function Build-SectionHeader ($sec, $bar, $lbl, $title) {
        $bar.Dock      = 'Top'
        $bar.Height    = 2
        $bar.BackColor = $C_SEP

        $lbl.Text      = "  $title"
        $lbl.Dock      = 'Top'
        $lbl.Height    = 22
        $lbl.Font      = $F_SEC
        $lbl.ForeColor = [System.Drawing.Color]::White
        $lbl.BackColor = $C_BG3
        $lbl.TextAlign = 'MiddleLeft'

        # Reihenfolge: lbl(Fill/index-0 nach bar), bar zuletzt -> bar erscheint oben
        $sec.Controls.Add($lbl)   # index 0 -> spaeter verarbeitet (nach bar)
        $sec.Controls.Add($bar)   # index 1 -> zuerst verarbeitet -> ganz oben
    }
    #endregion

    #region ── Event Handlers ─────────────────────────────────────────────────
    $CenterIniButtons = {
        $resetRight  = $btnClearLog.Right
        $beendenLeft = $panelButtons.ClientSize.Width - $btnBeendenWrapper.Width
        $available   = $beendenLeft - $resetRight
        $total       = $btnSaveIni.Width + 8 + $btnLoadIni.Width
        $x           = $resetRight + [int](($available - $total) / 2)
        $btnSaveIni.Left = $x
        $btnLoadIni.Left = $x + $btnSaveIni.Width + 8
    }

    $CenterPathButtons = {
        $btns      = @($btnQuelle, $btnZiel, $btnLogOrdner)
        $dots      = @($lblDotQuelle, $lblDotZiel, $lblDotLog)
        $lbls      = @($lblQuelle, $lblZiel, $lblLog)
        $btnH      = $btns[0].Height
        $rowGap    = 12
        $rowStep   = $btnH + $rowGap
        $totalSpan = $btns.Count * $btnH + ($btns.Count - 1) * $rowGap
        $startY    = [int](($secPfadeContent.ClientSize.Height - $totalSpan) / 2)
        for ($i = 0; $i -lt $btns.Count; $i++) {
            $y = $startY + $i * $rowStep
            $btns[$i].Top = $y
            $dots[$i].Top = $y
            $lbls[$i].Top = $y
        }
        $btnQuelleMode.Top = $startY
    }

    $panelButtons_Resize     = { & $CenterIniButtons }
    $secPfadeContent_Resize  = { & $CenterPathButtons }

    $formMain_Load = {
        Set-QuelleMode 'folder'
        # Quelle und Ziel beim Start immer leer – Pfade nur per Profil laden
        if ($script:defaultLogEnabled -and $script:defaultLogPath) {
            Set-PathLabel $lblLog $script:defaultLogPath
        }
        Update-StartButton
        Update-PathStatus
        & $CenterIniButtons
        & $CenterPathButtons
    }

    $btnQuelleMode_Click = {
        $newMode = if ($script:quelleMode -eq 'folder') { 'file' } else { 'folder' }
        Set-QuelleMode $newMode
        # Pfad zurücksetzen wenn Modus wechselt
        $lblQuelle.Text      = $T.LblNoPath
        $lblQuelle.ForeColor = $C_WARN
        $lblQuelle.Tag       = $null
        $lblDotQuelle.ForeColor = $C_BG
        Update-StartButton
        Update-PathStatus
    }

    $btnQuelle_Click = {
        $init = if ($lblQuelle.Tag) { $lblQuelle.Tag } else { $defaultDir }
        if ($script:quelleMode -eq 'file') {
            $p = Show-OpenFileDialog $init
        } else {
            $p = Show-FolderDialog $T.DlgFolderSrc $init
        }
        if ($p) { Set-PathLabel $lblQuelle $p; Write-Ini $lblQuelle.Tag $lblZiel.Tag $lblLog.Tag $script:quelleMode; Update-StartButton; Update-PathStatus }
    }
    $btnZiel_Click = {
        $init = if ($lblZiel.Tag) { $lblZiel.Tag } else { $defaultDir }
        $p = Show-FolderDialog $T.DlgFolderDst $init
        if ($p) { Set-PathLabel $lblZiel $p; Write-Ini $lblQuelle.Tag $lblZiel.Tag $lblLog.Tag $script:quelleMode; Update-StartButton; Update-PathStatus }
    }
    $btnLogOrdner_Click = {
        $init = if ($lblLog.Tag) { $lblLog.Tag } else { $defaultDir }
        $p = Show-FolderDialog $T.DlgFolderLog $init
        if ($p) { Set-PathLabel $lblLog $p; Write-Ini $lblQuelle.Tag $lblZiel.Tag $lblLog.Tag $script:quelleMode; Update-StartButton; Update-PathStatus }
    }

    $btnClearLog_Click = {
        $rtbLog.Clear()
        foreach ($lbl in @($lblQuelle, $lblZiel, $lblLog)) {
            $lbl.Text      = $T.LblNoPath
            $lbl.ForeColor = $C_WARN
            $lbl.Tag       = $null
        }
        foreach ($dot in @($lblDotQuelle, $lblDotZiel, $lblDotLog)) {
            $dot.ForeColor = $C_BG   # unsichtbar
        }
        $lblStatusPaths.Text      = ''
        $lblStatusPaths.ForeColor = $C_FG2
        Set-QuelleMode 'folder'
        $chkDelete.Checked     = $false
        $chkDeleteFile.Checked = $false
        # Default Log-Pfad wieder eintragen wenn aktiviert
        if ($script:defaultLogEnabled -and $script:defaultLogPath) {
            Set-PathLabel $lblLog $script:defaultLogPath
            $lblDotLog.ForeColor = $C_BG   # Dot-Farbe wird von Update-PathStatus gesetzt
        }
        Write-Ini '' '' ($lblLog.Tag) ''
        Update-StartButton
        Update-PathStatus
        Set-Status $T.StatusReady
    }

    $btnSaveIni_Click = {
        $profilesDir = Join-Path $appDir 'profiles'
        if (-not (Test-Path $profilesDir)) { New-Item -ItemType Directory -Path $profilesDir | Out-Null }

        $prefix = if ($script:quelleMode -eq 'file') { 'File_' } else { 'Folder_' }
        $name = Show-InputBox $T.DlgSavePrompt 'Backup' $prefix
        if (-not $name) { return }
        $name = $name -replace '[\\/:*?"<>|]', '_'
        if (-not $name.ToLower().EndsWith('.ini')) { $name += '.ini' }
        $file = Join-Path $profilesDir $name

        @(
            '[Paths]',
            "Source      = $($lblQuelle.Tag)",
            "Destination = $($lblZiel.Tag)",
            "LogFolder   = $($lblLog.Tag)",
            "SourceMode  = $($script:quelleMode)",
            '',
            '[Options]',
            "Verify      = $($chkVerify.Checked)",
            "Delete      = $($chkDelete.Checked)",
            "DeleteFile  = $($chkDeleteFile.Checked)"
        ) | Set-Content -Path $file -Encoding UTF8
        Set-Status ($T.StatusSaved -f $name)
    }

    $btnLoadIni_Click = {
        $profilesDir = Join-Path $appDir 'profiles'
        $file = Show-ProfileList $profilesDir
        if (-not $file) { return }

        $cfg = @{ Source=''; Destination=''; LogFolder=''; Verify='True'; Delete='False'; DeleteFile='False'; SourceMode='folder' }
        Get-Content $file -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^\s*(\w+)\s*=\s*(.*)$') {
                $k = $matches[1].Trim(); $v = $matches[2].Trim()
                if ($cfg.ContainsKey($k)) { $cfg[$k] = $v }
            }
        }
        Set-QuelleMode $cfg.SourceMode
        if ($cfg.Source)      { Set-PathLabel $lblQuelle $cfg.Source }
        if ($cfg.Destination) { Set-PathLabel $lblZiel   $cfg.Destination }
        if ($cfg.LogFolder)   { Set-PathLabel $lblLog    $cfg.LogFolder }
        $chkVerify.Checked     = ($cfg.Verify      -eq 'True')
        $chkDelete.Checked     = ($cfg.Delete      -eq 'True')
        $chkDeleteFile.Checked = ($cfg.DeleteFile  -eq 'True')
        Write-Ini $lblQuelle.Tag $lblZiel.Tag $lblLog.Tag $script:quelleMode
        Update-StartButton
        Update-PathStatus
        Set-Status ($T.StatusLoaded -f [System.IO.Path]::GetFileName($file))
    }

    $btnBeenden_Click          = { $formMain.Close() }
    $btnLang_Click             = { Show-LangDialog }
    $linkCopyright_LinkClicked = { Start-Process $APP_URL }

    # Hilfsfunktion: Backup-Buttons nach Abschluss/Fehler zuruecksetzen
    function Reset-StartButton {
        $btnStart.Enabled    = $true
        $btnStart.Text       = $T.BtnStart
        $btnStart.BackColor  = $C_ACCENT
        $btnStart.ForeColor  = [System.Drawing.Color]::White
        $progressBar.Visible = $false
    }

    $btnStart_Click = {
        $src = $lblQuelle.Tag
        $dst = $lblZiel.Tag
        $log = $lblLog.Tag

        if (-not ($src -and $dst -and $log)) {
            [System.Windows.Forms.MessageBox]::Show(
                $T.MsgNoPaths, $T.MsgHint, 'OK', 'Warning') | Out-Null
            return
        }
        if (-not (Test-Path $src)) {
            [System.Windows.Forms.MessageBox]::Show(
                ($T.MsgNoSource -f $src), $T.MsgError, 'OK', 'Error') | Out-Null
            return
        }
        if ($chkDelete.Checked -and (Test-Path $dst)) {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                ($T.MsgDeleteWarn -f $dst), $T.MsgDeleteTitle, 'YesNo', 'Warning')
            if ($ans -ne 'Yes') { return }
        }
        if ($chkDeleteFile.Checked -and $script:quelleMode -eq 'file') {
            $dstFile = Join-Path $dst ([System.IO.Path]::GetFileName($src))
            if (Test-Path $dstFile) {
                $ans = [System.Windows.Forms.MessageBox]::Show(
                    ($T.MsgDeleteFileWarn -f $dstFile), $T.MsgDeleteTitle, 'YesNo', 'Warning')
                if ($ans -ne 'Yes') { return }
                Remove-Item $dstFile -Force -ErrorAction SilentlyContinue
            }
        }

        $btnStart.Enabled    = $false
        $btnStart.Text       = $T.BtnRunning
        $btnStart.BackColor  = $C_BG2
        $progressBar.Visible = $true
        $rtbLog.Clear()

        $doVerify = $chkVerify.Checked
        $doDelete = $chkDelete.Checked
        $ts       = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $logFile  = Join-Path $log "Backup_$ts.log"
        $hashFile = Join-Path $log "Checksum_$ts.log"

        if (-not (Test-Path $log)) { New-Item -ItemType Directory -Path $log | Out-Null }

        Write-LogLine ($T.LogStarted -f $ts) ([System.Drawing.Color]::CornflowerBlue)
        Write-LogLine ($T.LogSrc    -f $src) $C_FG2
        Write-LogLine ($T.LogDst    -f $dst) $C_FG2
        Write-LogLine ($T.LogFile2  -f $logFile) $C_FG2
        Write-LogLine ('-' * 72)

        # Gemeinsamer Job-State fuer alle Timer-Phasen
        $script:backupJob = @{
            State      = ''
            LogFile    = $logFile
            HashFile   = $hashFile
            DoVerify   = $doVerify
            Src        = $src
            Dst        = $dst
            FileMode   = ($script:quelleMode -eq 'file')
            LogPos     = 0L
            LogFound   = $false
            Proc       = $null
            DelJob     = $null
            VerifyJob  = $null
        }

        if ($doDelete -and (Test-Path $dst)) {
            # ── Phase 1: Loeschen als Background-Job (blockiert UI nicht) ─────
            Set-Status $T.StatusDeleting
            Write-LogLine $T.LogDeleting $C_WARN
            $script:backupJob.State  = 'deleting'
            $script:backupJob.DelJob = Start-Job -ArgumentList $dst -ScriptBlock {
                param($d)
                try   { Remove-Item -Recurse -Force -Path $d -ErrorAction Stop
                        [PSCustomObject]@{ OK=$true;  Err='' } }
                catch { [PSCustomObject]@{ OK=$false; Err=$_.ToString() } }
            }
        } else {
            # ── Phase 2 direkt: Robocopy starten ─────────────────────────────
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
            Set-Status $T.StatusRunning
            $rcArgs = Get-RcArgs $script:backupJob
            $script:backupJob.State = 'robocopy'
            $script:backupJob.Proc  = Start-Process -FilePath 'robocopy' `
                                          -ArgumentList $rcArgs -PassThru -WindowStyle Hidden
        }
        $timerRobocopy.Start()
    }

    # Timer-Tick: Zustandsautomat  robocopy → (verify →) fertig
    # Laeuft auf dem UI-Thread → WinForms-Message-Pump bleibt aktiv
    $timerRobocopy_Tick = {
        $job = $script:backupJob
        if (-not $job) { $timerRobocopy.Stop(); return }

        # ════════════════════════════════════════════════════════════════════════
        # Zustand: deleting  (Remove-Item als Hintergrundjob)
        # ════════════════════════════════════════════════════════════════════════
        if ($job.State -eq 'deleting') {
            $dj = $job.DelJob
            if ($dj.State -ne 'Completed') { return }   # Job laeuft noch

            $res = Receive-Job $dj -ErrorAction SilentlyContinue
            Remove-Job $dj

            if (-not $res.OK) {
                Write-LogLine ($T.LogDeleteErr -f $res.Err) $C_ERR
                Set-Status $T.StatusDelFail
                $timerRobocopy.Stop(); $script:backupJob = $null
                Reset-StartButton; return
            }

            Write-LogLine $T.LogDeleted $C_OK
            $dst = $job.Dst
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst | Out-Null }
            Set-Status $T.StatusRunning

            # Robocopy starten und in Phase 'robocopy' wechseln
            $rcArgs = Get-RcArgs $job
            $job.Proc  = Start-Process -FilePath 'robocopy' -ArgumentList $rcArgs `
                                       -PassThru -WindowStyle Hidden
            $job.State = 'robocopy'
            return
        }

        # ════════════════════════════════════════════════════════════════════════
        # Zustand: robocopy
        # ════════════════════════════════════════════════════════════════════════
        if ($job.State -eq 'robocopy') {

            # Live-Ausgabe: neue Zeilen gebatcht lesen → ein einziger AppendText+ScrollToCaret
            # Jedes einzelne Write-LogLine würde ScrollToCaret aufrufen → UI-Stutter bei vielen Zeilen
            if (-not $job.LogFound) { $job.LogFound = (Test-Path $job.LogFile) }
            if ($job.LogFound) {
                try {
                    $fs = [System.IO.File]::Open(
                        $job.LogFile,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite)
                    $fs.Seek($job.LogPos, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $sr  = New-Object System.IO.StreamReader(
                        $fs, [System.Text.Encoding]::GetEncoding(850))
                    $sb  = New-Object System.Text.StringBuilder
                    while (-not $sr.EndOfStream) { $sb.AppendLine($sr.ReadLine()) | Out-Null }
                    $job.LogPos = $fs.Position
                    $sr.Close(); $fs.Close()
                    if ($sb.Length -gt 0) {
                        $rtbLog.SelectionStart  = $rtbLog.TextLength
                        $rtbLog.SelectionLength = 0
                        $rtbLog.SelectionColor  = $C_FG
                        $rtbLog.AppendText($sb.ToString())
                        $rtbLog.ScrollToCaret()
                    }
                } catch { }
            }

            if (-not $job.Proc.HasExited) { return }   # Robocopy laeuft noch

            $rc = $job.Proc.ExitCode
            if ($rc -le 7) {
                Write-LogLine ($T.LogRcOK -f $rc) $C_OK
            } else {
                Write-LogLine ($T.LogRcErr -f $rc) $C_ERR
                Set-Status ($T.StatusErrCode -f $rc)
                $timerRobocopy.Stop(); $script:backupJob = $null
                Reset-StartButton; return
            }

            if ($job.DoVerify) {
                # SHA256-Verifikation als Hintergrundjob starten (blockiert nicht den UI-Thread)
                Write-LogLine ("`n" + '-' * 72)
                Write-LogLine $T.LogVerifyStart ([System.Drawing.Color]::CornflowerBlue)
                Set-Status $T.StatusVerify

                $vj = Start-Job -ArgumentList $job.Src, $job.Dst, $job.FileMode -ScriptBlock {
                    param($src, $dst, $fileMode)
                    function Get-H ($p) {
                        $sha = [System.Security.Cryptography.SHA256]::Create()
                        $fs  = [System.IO.File]::OpenRead($p)
                        try   { [BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-' }
                        finally { $fs.Close(); $sha.Dispose() }
                    }
                    $miss = 0; $msgs = @()
                    if ($fileMode) {
                        # Einzeldatei: nur diese eine Datei prüfen
                        $fileName = [System.IO.Path]::GetFileName($src)
                        $dstP     = Join-Path $dst $fileName
                        if (-not (Test-Path $dstP)) {
                            $msgs += "__MISS__$fileName"; $miss++
                        } elseif ((Get-H $src) -ne (Get-H $dstP)) {
                            $msgs += "__MISM__$fileName"; $miss++
                        }
                    } else {
                        Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
                            $rel  = $_.FullName.Substring($src.Length).TrimStart([char]92)
                            $dstP = Join-Path $dst $rel
                            if (-not (Test-Path $dstP)) {
                                $msgs += "__MISS__$rel"; $miss++
                            } elseif ((Get-H $_.FullName) -ne (Get-H $dstP)) {
                                $msgs += "__MISM__$rel"; $miss++
                            }
                        }
                    }
                    [PSCustomObject]@{ Miss = $miss; Msgs = $msgs }
                }
                $job.VerifyJob = $vj
                $job.State     = 'verify'
                # Timer laeuft weiter → naechster Tick prueft den Verify-Job
            } else {
                # Keine Verifikation – direkt fertig
                Write-LogLine ("`n" + '-' * 72)
                Write-LogLine $T.LogDone $C_OK
                Set-Status $T.StatusDone
                $doneLog = $job.LogFile
                $timerRobocopy.Stop(); $script:backupJob = $null   # VOR MessageBox stoppen!
                Reset-StartButton
                [System.Windows.Forms.MessageBox]::Show(
                    ($T.MsgDoneText -f $doneLog), $T.MsgDoneTitle, 'OK', 'Information') | Out-Null
            }
            return
        }

        # ════════════════════════════════════════════════════════════════════════
        # Zustand: verify  (SHA256-Hintergrundjob)
        # ════════════════════════════════════════════════════════════════════════
        if ($job.State -eq 'verify') {
            $vj = $job.VerifyJob
            if ($vj.State -ne 'Completed') { return }   # Job laeuft noch

            $res = Receive-Job $vj -ErrorAction SilentlyContinue
            Remove-Job $vj

            $miss = $res.Miss
            $rawMsgs = @($res.Msgs)

            # Interne Codes in aktive Sprache uebersetzen und anzeigen
            $translatedMsgs = foreach ($m in $rawMsgs) {
                if     ($m.StartsWith('__MISS__')) { $tl = $T.LogMissing  -f $m.Substring(8); Write-LogLine $tl $C_WARN; $tl }
                elseif ($m.StartsWith('__MISM__')) { $tl = $T.LogMismatch -f $m.Substring(8); Write-LogLine $tl $C_ERR;  $tl }
                else                              { Write-LogLine $m; $m }
            }

            $summary = if ($miss -eq 0) { $T.LogAllOK } else { $T.LogDiscrep -f $miss }
            ($translatedMsgs + $summary) | Set-Content -Path $job.HashFile -Encoding UTF8

            if ($miss -eq 0) {
                Write-LogLine $T.LogVerifyOK $C_OK
                Write-LogLine ($T.LogChecksumFile -f $job.HashFile) $C_FG2
            } else {
                Write-LogLine ($T.LogVerifyWarn   -f $miss)         $C_ERR
                Write-LogLine ($T.LogVerifyDetail -f $job.HashFile) $C_WARN
            }

            Write-LogLine ("`n" + '-' * 72)
            Write-LogLine $T.LogDone $C_OK
            Set-Status $T.StatusDone
            $doneLog = $job.LogFile
            $timerRobocopy.Stop(); $script:backupJob = $null   # VOR MessageBox stoppen!
            Reset-StartButton
            [System.Windows.Forms.MessageBox]::Show(
                ($T.MsgDoneText -f $doneLog), $T.MsgDoneTitle, 'OK', 'Information') | Out-Null
        }
    }
    #endregion

    #region ── Form Code (SuspendLayout) ──────────────────────────────────────
    $formMain.SuspendLayout()
    $panelHeader.SuspendLayout()
    $panelFooter.SuspendLayout()
    $panelMain.SuspendLayout()
    $secPfade.SuspendLayout()
    $secPfadeContent.SuspendLayout()
    $secOpt.SuspendLayout()
    $secOptContent.SuspendLayout()
    $panelButtons.SuspendLayout()
    $panelStatus.SuspendLayout()
    $secLog.SuspendLayout()

    #-- formMain ---------------------------------------------------------------
    $formMain.Text              = 'Robocopy App'
    $formMain.ClientSize        = New-Object 'System.Drawing.Size'(820, 620)
    $formMain.MinimumSize       = $formMain.Size
    $formMain.BackColor         = $C_BG
    $formMain.ForeColor         = $C_FG
    $formMain.Font              = $F_UI
    $formMain.StartPosition     = 'CenterScreen'
    $formMain.FormBorderStyle   = 'Sizable'
    $formMain.AutoScaleMode     = [System.Windows.Forms.AutoScaleMode]::Dpi
    $formMain.AutoScaleDimensions = New-Object 'System.Drawing.SizeF'(96, 96)

    #-- panelHeader (Dock=Top) -------------------------------------------------
    $panelHeader.Dock      = 'Top'
    $panelHeader.Height    = 54
    $panelHeader.BackColor = $C_HDR
    $labelTitle.Text      = '  Easy Robocopy interface - ERi-Backup-App'
    $labelTitle.Dock      = 'Fill'
    $labelTitle.Font      = New-Font 'Segoe UI Semibold' 13
    $labelTitle.ForeColor = [System.Drawing.Color]::White
    $labelTitle.TextAlign = 'MiddleLeft'

    # Sprach-Schaltfläche (Zahnrad) rechts im Header
    $btnLang.Text      = [char]0x2699     # ⚙
    $btnLang.Dock      = 'Right'
    $btnLang.Width     = 46
    $btnLang.FlatStyle = 'Flat'
    $btnLang.FlatAppearance.BorderSize         = 0
    $btnLang.FlatAppearance.MouseOverBackColor = $C_ACCH
    $btnLang.BackColor = $C_HDR
    $btnLang.ForeColor = [System.Drawing.Color]::White
    $btnLang.Font      = New-Font 'Segoe UI' 14
    $btnLang.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $ttLang = New-Object 'System.Windows.Forms.ToolTip'
    $ttLang.SetToolTip($btnLang, $T.DlgLangTitle)
    # Dock=Right: zuerst hinzufügen damit labelTitle (Fill) den Rest bekommt
    $panelHeader.Controls.Add($btnLang)
    $panelHeader.Controls.Add($labelTitle)

    #-- panelFooter (Dock=Bottom) ----------------------------------------------
    $panelFooter.Dock      = 'Bottom'
    $panelFooter.Height    = 28
    $panelFooter.BackColor = $C_FOOT
    $labelVersion.Text      = "  Version: $APP_VERSION"
    $labelVersion.Dock      = 'Left'
    $labelVersion.Width     = 200
    $labelVersion.Font      = $F_SM
    $labelVersion.ForeColor = $C_DIMTXT
    $labelVersion.TextAlign = 'MiddleLeft'
    $panelFooter.Controls.Add($labelVersion)
    $linkCopyright.Text            = $APP_COPYRIGHT
    $linkCopyright.Dock            = 'Right'
    $linkCopyright.Width           = 260
    $linkCopyright.Font            = $F_SM
    $linkCopyright.ForeColor       = $C_DIMTXT
    $linkCopyright.LinkColor       = $C_ACCENT
    $linkCopyright.ActiveLinkColor = New-Color '#a78bfa'
    $linkCopyright.TextAlign       = 'MiddleRight'
    $linkCopyright.Padding         = New-Object 'System.Windows.Forms.Padding'(0,0,8,0)
    $panelFooter.Controls.Add($linkCopyright)

    #-- panelMain (Dock=Fill, Padding = Raender) -------------------------------
    $panelMain.Dock      = 'Fill'
    $panelMain.BackColor = $C_BG
    $panelMain.Padding   = New-Object 'System.Windows.Forms.Padding'(12, 10, 12, 6)

    #== Pfade-Sektion ==========================================================
    $secPfade.Dock      = 'Top'
    $secPfade.Height    = 170
    $secPfade.BackColor = $C_BG

    # Content ZUERST (index 0, Fill) -> wird zuletzt gedockt (fuellt Rest)
    $secPfadeContent.Dock      = 'Fill'
    $secPfadeContent.BackColor = $C_BG
    $secPfade.Controls.Add($secPfadeContent)

    # Bar + Title danach (index 1+2) -> hoeherer Index = zuerst gedockt = ganz oben
    Build-SectionHeader $secPfade $secPfadeBar $secPfadeTitle $T.SecPfade

    # Pfad-Zeilen im Content-Panel (Y startet bei 4 statt 24 - kein GroupBox-Titel-Offset)
    function Set-PathRow ($parent, $btn, $dot, $lbl, $caption, $rowIdx) {
        $y = 13 + $rowIdx * 44
        $btn.Text      = $caption
        $btn.Location  = New-Object 'System.Drawing.Point'(10, $y)
        $btn.Size      = New-Object 'System.Drawing.Size'(180, 32)
        $btn.BackColor = $C_BG2
        $btn.ForeColor = $C_FG
        $btn.Font      = $F_SEC
        $btn.FlatStyle = 'Flat'
        $btn.FlatAppearance.BorderColor        = $C_ACCENT
        $btn.FlatAppearance.BorderSize         = 1
        $btn.FlatAppearance.MouseOverBackColor = $C_ACCENT
        $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
        $btn.Anchor    = $ANC_TL
        $dot.Text      = [char]0x25CF   # ● gefüllter Kreis
        $dot.Location  = New-Object 'System.Drawing.Point'(197, $y)
        $dot.Size      = New-Object 'System.Drawing.Size'(18, 32)
        $dot.Font      = New-Font 'Segoe UI' 14
        $dot.ForeColor = $C_BG             # unsichtbar bis Pfad gesetzt
        $dot.TextAlign = 'MiddleCenter'
        $dot.Anchor    = $ANC_TL
        $lbl.Text      = $T.LblNoPath
        $lbl.Location  = New-Object 'System.Drawing.Point'(219, $y)
        $lbl.Size      = New-Object 'System.Drawing.Size'(561, 32)
        $lbl.Font      = $F_MONO
        $lbl.ForeColor = $C_WARN
        $lbl.TextAlign = 'MiddleLeft'
        $lbl.Anchor    = $ANC_TLR
        $parent.Controls.Add($btn)
        $parent.Controls.Add($dot)
        $parent.Controls.Add($lbl)
    }
    Set-PathRow $secPfadeContent $btnQuelle    $lblDotQuelle $lblQuelle $T.BtnQuelle  0
    Set-PathRow $secPfadeContent $btnZiel      $lblDotZiel   $lblZiel   $T.BtnZiel    1
    Set-PathRow $secPfadeContent $btnLogOrdner $lblDotLog    $lblLog    $T.BtnLogOrd  2

    # Quelle-Button schmaler + Mode-Toggle-Button
    $btnQuelle.Width = 152
    $btnQuelle.Text  = $T.BtnQuelleFolder   # initialer Text mit Modus-Anzeige
    $btnQuelleMode.Text      = [System.Char]::ConvertFromUtf32(0x1F4C1)   # 📁
    $btnQuelleMode.Location  = New-Object 'System.Drawing.Point'(164, 13)
    $btnQuelleMode.Size      = New-Object 'System.Drawing.Size'(26, 32)
    $btnQuelleMode.Font      = New-Font 'Segoe UI Emoji' 11
    $btnQuelleMode.BackColor = $C_BG2
    $btnQuelleMode.ForeColor = $C_FG
    $btnQuelleMode.FlatStyle = 'Flat'
    $btnQuelleMode.FlatAppearance.BorderColor        = $C_ACCENT
    $btnQuelleMode.FlatAppearance.BorderSize         = 1
    $btnQuelleMode.FlatAppearance.MouseOverBackColor = $C_ACCENT
    $btnQuelleMode.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnQuelleMode.Anchor    = $ANC_TL
    $secPfadeContent.Controls.Add($btnQuelleMode)

    #-- spacer1 ---------------------------------------------------------------
    $sp1 = New-Object 'System.Windows.Forms.Panel'
    $sp1.Dock = 'Top'; $sp1.Height = 6; $sp1.BackColor = $C_BG

    #== Optionen-Sektion =======================================================
    $secOpt.Dock      = 'Top'
    $secOpt.Height    = 118
    $secOpt.BackColor = $C_BG

    # Content ZUERST (index 0, Fill)
    $secOptContent.Dock      = 'Fill'
    $secOptContent.BackColor = $C_BG
    $secOpt.Controls.Add($secOptContent)

    # Bar + Title danach (index 1+2)
    Build-SectionHeader $secOpt $secOptBar $secOptTitle $T.SecOpt

    function Set-CheckBox ($cb, $parent, $text, $yPos, $checked) {
        $cb.Text      = "  $text"
        $cb.Checked   = $checked
        $cb.Location  = New-Object 'System.Drawing.Point'(10, $yPos)
        $cb.Size      = New-Object 'System.Drawing.Size'(780, 24)
        $cb.Font      = $F_UI
        $cb.ForeColor = $C_FG
        $cb.BackColor = $C_BG
        $cb.Anchor    = $ANC_TLR
        $parent.Controls.Add($cb)
    }
    Set-CheckBox $chkVerify      $secOptContent $T.ChkVerify     4  $true
    Set-CheckBox $chkDelete      $secOptContent $T.ChkDelete     32 $false
    Set-CheckBox $chkDeleteFile  $secOptContent $T.ChkDeleteFile 60 $false
    $chkDeleteFile.Enabled = $false   # initial Ordner-Modus → ausgegraut

    # Im Datei-Modus: chkDelete deaktiviert chkDeleteFile (Ordner-Löschung schliesst Datei ein)
    $chkDelete.add_CheckedChanged({
        if ($script:quelleMode -eq 'file') {
            $chkDeleteFile.Enabled = -not $chkDelete.Checked
            if ($chkDelete.Checked) { $chkDeleteFile.Checked = $false }
        }
    })

    #-- spacer2 ---------------------------------------------------------------
    $sp2 = New-Object 'System.Windows.Forms.Panel'
    $sp2.Dock = 'Top'; $sp2.Height = 6; $sp2.BackColor = $C_BG

    #-- panelButtons (Dock=Top) -----------------------------------------------
    $panelButtons.Dock      = 'Top'
    $panelButtons.Height    = 52
    $panelButtons.BackColor = $C_BG

    $btnStart.Text      = $T.BtnStart
    $btnStart.Location  = New-Object 'System.Drawing.Point'(0, 7)
    $btnStart.Size      = New-Object 'System.Drawing.Size'(180, 38)
    $btnStart.BackColor = $C_BG2
    $btnStart.ForeColor = $C_FG2
    $btnStart.Font      = $F_BOLD
    $btnStart.FlatStyle = 'Flat'
    $btnStart.FlatAppearance.BorderSize         = 0
    $btnStart.FlatAppearance.MouseOverBackColor = $C_ACCH
    $btnStart.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnStart.Enabled   = $false
    $btnStart.Anchor    = $ANC_TL

    $btnClearLog.Text      = $T.BtnReset
    $btnClearLog.Location  = New-Object 'System.Drawing.Point'(188, 7)
    $btnClearLog.Size      = New-Object 'System.Drawing.Size'(135, 38)
    $btnClearLog.BackColor = $C_FG2
    $btnClearLog.ForeColor = $C_BG2
    $btnClearLog.Font      = $F_UI
    $btnClearLog.FlatStyle = 'Flat'
    $btnClearLog.FlatAppearance.BorderColor        = $C_FG2
    $btnClearLog.FlatAppearance.MouseOverBackColor = $C_ACCENT
    $btnClearLog.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnClearLog.Anchor    = $ANC_TL

    $btnSaveIni.Text      = $T.BtnSave
    $btnSaveIni.Location  = New-Object 'System.Drawing.Point'(331, 7)
    $btnSaveIni.Size      = New-Object 'System.Drawing.Size'(135, 38)
    $btnSaveIni.BackColor = $C_BG2
    $btnSaveIni.ForeColor = $C_FG2
    $btnSaveIni.Font      = $F_UI
    $btnSaveIni.FlatStyle = 'Flat'
    $btnSaveIni.FlatAppearance.BorderColor        = New-Color '#4a5070'
    $btnSaveIni.FlatAppearance.BorderSize         = 1
    $btnSaveIni.FlatAppearance.MouseOverBackColor = New-Color '#3a3a5e'
    $btnSaveIni.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnSaveIni.Anchor    = [System.Windows.Forms.AnchorStyles]::None

    $btnLoadIni.Text      = $T.BtnLoad
    $btnLoadIni.Location  = New-Object 'System.Drawing.Point'(474, 7)
    $btnLoadIni.Size      = New-Object 'System.Drawing.Size'(135, 38)
    $btnLoadIni.BackColor = $C_BG2
    $btnLoadIni.ForeColor = $C_FG2
    $btnLoadIni.Font      = $F_UI
    $btnLoadIni.FlatStyle = 'Flat'
    $btnLoadIni.FlatAppearance.BorderColor        = New-Color '#4a5070'
    $btnLoadIni.FlatAppearance.BorderSize         = 1
    $btnLoadIni.FlatAppearance.MouseOverBackColor = New-Color '#3a3a5e'
    $btnLoadIni.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnLoadIni.Anchor    = [System.Windows.Forms.AnchorStyles]::None

    $btnBeenden.Text      = $T.BtnQuit
    $btnBeenden.Location  = New-Object 'System.Drawing.Point'(5, 7)
    $btnBeenden.Size      = New-Object 'System.Drawing.Size'(110, 38)
    $btnBeenden.BackColor = New-Color '#232b2a'
    $btnBeenden.ForeColor = [System.Drawing.Color]::White
    $btnBeenden.Font      = $F_BOLD
    $btnBeenden.FlatStyle = 'Flat'
    $btnBeenden.FlatAppearance.BorderSize         = 0
    $btnBeenden.FlatAppearance.MouseOverBackColor = New-Color '#686465'
    $btnBeenden.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnBeenden.Anchor    = $ANC_TL

    # Wrapper Dock=Right: verhindert Anchor-Fehler bei SuspendLayout
    $btnBeendenWrapper.Dock      = 'Right'
    $btnBeendenWrapper.Width     = 120
    $btnBeendenWrapper.BackColor = $C_BG
    $btnBeendenWrapper.Controls.Add($btnBeenden)
    # Dock=Right: letztes Control = hoeher Index = rechts aussen (korrekte Position)
    $panelButtons.Controls.AddRange(@($btnStart, $btnClearLog, $btnSaveIni, $btnLoadIni, $btnBeendenWrapper))

    #-- spacer3 ---------------------------------------------------------------
    $sp3 = New-Object 'System.Windows.Forms.Panel'
    $sp3.Dock = 'Top'; $sp3.Height = 6; $sp3.BackColor = $C_BG

    #-- progressBar (Dock=Top, Marquee waehrend Robocopy/Verify laeuft) -------
    $progressBar.Dock    = 'Top'
    $progressBar.Height  = 6
    $progressBar.Style   = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progressBar.MarqueeAnimationSpeed = 25
    $progressBar.Visible = $false

    #-- panelStatus (Dock=Top) ------------------------------------------------
    $panelStatus.Dock      = 'Top'
    $panelStatus.Height    = 30
    $panelStatus.BackColor = $C_BG2
    $lblStatusPaths.Text      = ''
    $lblStatusPaths.Dock      = 'Right'
    $lblStatusPaths.Width     = 280
    $lblStatusPaths.Font      = $F_UI
    $lblStatusPaths.ForeColor = $C_FG2
    $lblStatusPaths.TextAlign = 'MiddleRight'
    $lblStatusPaths.Padding   = New-Object 'System.Windows.Forms.Padding'(0,0,8,0)
    $lblStatus.Text      = $T.StatusReady
    $lblStatus.Dock      = 'Fill'
    $lblStatus.Font      = $F_UI
    $lblStatus.ForeColor = $C_FG2
    $lblStatus.TextAlign = 'MiddleLeft'
    $lblStatus.Padding   = New-Object 'System.Windows.Forms.Padding'(8,0,0,0)
    # Reihenfolge: Fill zuerst, dann Right (Right wird zuerst gedockt)
    $panelStatus.Controls.Add($lblStatus)
    $panelStatus.Controls.Add($lblStatusPaths)

    #-- spacer4 ---------------------------------------------------------------
    $sp4 = New-Object 'System.Windows.Forms.Panel'
    $sp4.Dock = 'Top'; $sp4.Height = 6; $sp4.BackColor = $C_BG

    #== Ausgabe-Sektion ========================================================
    $secLog.Dock      = 'Fill'
    $secLog.BackColor = $C_BG

    $secLogBar.Dock      = 'Top'
    $secLogBar.Height    = 2
    $secLogBar.BackColor = $C_SEP

    $secLogTitle.Text      = "  $($T.SecLog)"
    $secLogTitle.Dock      = 'Top'
    $secLogTitle.Height    = 22
    $secLogTitle.Font      = $F_SEC
    $secLogTitle.ForeColor = [System.Drawing.Color]::White
    $secLogTitle.BackColor = $C_BG3
    $secLogTitle.TextAlign = 'MiddleLeft'

    $rtbLog.Dock        = 'Fill'
    $rtbLog.BackColor   = $C_LOGBG
    $rtbLog.ForeColor   = $C_FG
    $rtbLog.Font        = $F_MONO
    $rtbLog.ReadOnly    = $true
    $rtbLog.BorderStyle = 'None'
    $rtbLog.ScrollBars  = 'None'
    $rtbLog.WordWrap    = $true

    # secLog Controls: rtbLog(Fill,0), secLogTitle(Top,1), secLogBar(Top,2)
    $secLog.Controls.Add($rtbLog)        # index 0, Fill
    $secLog.Controls.Add($secLogTitle)   # index 1, Top -> unterhalb Bar
    $secLog.Controls.Add($secLogBar)     # index 2, Top -> ganz oben

    #-- panelMain: Controls in Dock-Reihenfolge --------------------------------
    # Fill zuerst, dann Top rueckwaerts (letzter = ganz oben)
    $panelMain.Controls.Add($secLog)         # Fill
    $panelMain.Controls.Add($sp4)            # Top
    $panelMain.Controls.Add($panelStatus)    # Top
    $panelMain.Controls.Add($progressBar)    # Top (zwischen panelStatus und sp3)
    $panelMain.Controls.Add($sp3)            # Top
    $panelMain.Controls.Add($panelButtons)   # Top
    $panelMain.Controls.Add($sp2)            # Top
    $panelMain.Controls.Add($secOpt)         # Top
    $panelMain.Controls.Add($sp1)            # Top
    $panelMain.Controls.Add($secPfade)       # Top (oberster Inhalt)

    #-- Form: Dock-Reihenfolge -------------------------------------------------
    $formMain.Controls.Add($panelMain)    # Fill
    $formMain.Controls.Add($panelFooter)  # Bottom
    $formMain.Controls.Add($panelHeader)  # Top

    #-- Timer-Robocopy (Polling alle 500 ms) ----------------------------------
    $timerRobocopy.Interval = 500

    #-- ResumeLayout -----------------------------------------------------------
    $secLog.ResumeLayout($false)
    $panelStatus.ResumeLayout($false)
    $panelStatus.PerformLayout()
    $panelButtons.ResumeLayout($false)
    $secOptContent.ResumeLayout($false)
    $secOpt.ResumeLayout($false)
    $secPfadeContent.ResumeLayout($false)
    $secPfade.ResumeLayout($false)
    $panelMain.ResumeLayout($false)
    $panelFooter.ResumeLayout($false)
    $panelHeader.ResumeLayout($false)
    $formMain.ResumeLayout($false)
    #endregion

    #region ── Event-Verdrahtung ───────────────────────────────────────────────
    $formMain.add_Load($formMain_Load)
    $formMain.add_Shown({
        if ($formMain.Size.Width  -gt $formMain.MinimumSize.Width -or
            $formMain.Size.Height -gt $formMain.MinimumSize.Height) {
            $formMain.MinimumSize = $formMain.Size
        }
        & $CenterIniButtons
        & $CenterPathButtons
        Update-PathStatus
    })
    $panelButtons.add_Resize($panelButtons_Resize)
    $secPfadeContent.add_Resize($secPfadeContent_Resize)
    $btnQuelle.add_Click($btnQuelle_Click)
    $btnQuelleMode.add_Click($btnQuelleMode_Click)
    $btnZiel.add_Click($btnZiel_Click)
    $btnLogOrdner.add_Click($btnLogOrdner_Click)
    $btnStart.add_Click($btnStart_Click)
    $btnClearLog.add_Click($btnClearLog_Click)
    $btnSaveIni.add_Click($btnSaveIni_Click)
    $btnLoadIni.add_Click($btnLoadIni_Click)
    $btnBeenden.add_Click($btnBeenden_Click)
    $btnLang.add_Click($btnLang_Click)
    $linkCopyright.add_LinkClicked($linkCopyright_LinkClicked)
    $timerRobocopy.add_Tick($timerRobocopy_Tick)
    #endregion

    $formMain.ShowDialog() | Out-Null
    $formMain.Dispose()

} # end GenerateForm
#endregion ── ScriptForm Designer ──────────────────────────────────────────────

GenerateForm
