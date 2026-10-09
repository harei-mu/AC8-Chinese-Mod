# Read Steam launch options. The in-memory setter is used only by test fixtures;
# installation and uninstallation never write the real Steam configuration.
if (-not ('AC8SteamVdf' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
public static class AC8SteamVdf {
    class Token { public string Text; public int Start, End; public bool Brace; }
    class Node { public string Key; public Token Value; public int Close; public List<Node> Children=new List<Node>(); }
    static List<Token> Tokens(string s) {
        var result=new List<Token>(); int i=0;
        while(i<s.Length) {
            if(Char.IsWhiteSpace(s[i]) || s[i]=='\ufeff') {i++;continue;}
            if(s[i]=='/' && i+1<s.Length && s[i+1]=='/') {while(i<s.Length && s[i]!='\n') i++;continue;}
            int start=i;
            if(s[i]=='{' || s[i]=='}') {result.Add(new Token{Text=s[i++].ToString(),Start=start,End=i,Brace=true});continue;}
            if(s[i++]!='"') throw new FormatException("Unsupported Steam VDF syntax");
            var text=new StringBuilder(); bool closed=false;
            while(i<s.Length) {
                char c=s[i++]; if(c=='"') {closed=true;break;}
                if(c=='\\') {if(i==s.Length) throw new FormatException("Incomplete VDF escape"); char e=s[i++];
                    if(e=='n') c='\n'; else if(e=='r') c='\r'; else if(e=='t') c='\t'; else if(e=='\\'||e=='"') c=e;
                    else {text.Append('\\');c=e;}}
                text.Append(c);
            }
            if(!closed) throw new FormatException("Unterminated VDF string");
            result.Add(new Token{Text=text.ToString(),Start=start,End=i});
        } return result;
    }
    static List<Node> Parse(List<Token> tokens,ref int i,bool nested,out int close) {
        var nodes=new List<Node>();close=-1;
        while(i<tokens.Count) {
            if(tokens[i].Brace && tokens[i].Text=="}") {if(!nested) throw new FormatException("Unexpected VDF brace");close=tokens[i++].Start;return nodes;}
            Token key=tokens[i++]; if(key.Brace || i==tokens.Count) throw new FormatException("Missing VDF value");
            var node=new Node{Key=key.Text};
            if(tokens[i].Brace && tokens[i].Text=="{") {i++;int end;node.Children=Parse(tokens,ref i,true,out end);node.Close=end;}
            else {node.Value=tokens[i++];if(node.Value.Brace) throw new FormatException("Missing VDF value");}
            nodes.Add(node);
        }
        if(nested) throw new FormatException("Unclosed VDF object"); return nodes;
    }
    static Node Find(List<Node> nodes,string key) {
        Node result=null; foreach(var n in nodes) if(String.Equals(n.Key,key,StringComparison.OrdinalIgnoreCase)) {
            if(result!=null) throw new FormatException("Duplicate VDF key"); result=n;
        } return result;
    }
    static Node Apps(string s) {
        int i=0,close;var nodes=Parse(Tokens(s),ref i,false,out close);
        Node node=null; foreach(string key in new[]{"UserLocalConfigStore","Software","Valve","Steam","apps"}) {
            node=Find(nodes,key);if(node==null || node.Value!=null) throw new FormatException("Steam apps configuration not found");nodes=node.Children;
        }return node;
    }
    static string Quote(string value) {return "\""+value.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","\\r").Replace("\n","\\n").Replace("\t","\\t")+"\"";}
    public static string Get(string s) {
        Node app=Find(Apps(s).Children,"2288340");if(app==null) return null;
        Node opt=Find(app.Children,"LaunchOptions");if(opt==null) return null;
        if(opt.Value==null) throw new FormatException("Invalid LaunchOptions");return opt.Value.Text;
    }
    public static string Set(string s,string value) {
        Node apps=Apps(s),app=Find(apps.Children,"2288340");string nl=s.Contains("\r\n")?"\r\n":"\n";
        if(app==null) {if(value==null) return s;return s.Insert(apps.Close,nl+"\t\t\t\t\"2288340\""+nl+"\t\t\t\t{"+nl+"\t\t\t\t\t\"LaunchOptions\"\t\t"+Quote(value)+nl+"\t\t\t\t}"+nl);}
        Node opt=Find(app.Children,"LaunchOptions");
        if(opt==null) {if(value==null) return s;return s.Insert(app.Close,nl+"\t\t\t\t\t\"LaunchOptions\"\t\t"+Quote(value)+nl);}
        if(opt.Value==null) throw new FormatException("Invalid LaunchOptions");
        // Restore absent options as an empty value; the game originally receives no arguments.
        return s.Substring(0,opt.Value.Start)+Quote(value??"")+s.Substring(opt.Value.End);
    }
}
'@
}
function Get-SteamRoot([string]$SteamDir) {
    if (-not $SteamDir) { $SteamDir = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath }
    if (-not $SteamDir -or -not (Test-Path -LiteralPath (Join-Path $SteamDir 'steam.exe'))) { throw '未找到 Steam，请先安装并登录 Steam。' }
    return [IO.Path]::GetFullPath($SteamDir).TrimEnd('\')
}
function Get-SteamConfig([string]$SteamRoot) {
    $userRoot = Scoped-Path $SteamRoot 'userdata'
    $active = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction SilentlyContinue).ActiveUser
    if ($active) {
        $candidate = Scoped-Path $userRoot (([string]$active) + '\config\localconfig.vdf')
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $configs = @(Get-ChildItem -LiteralPath $userRoot -Directory | ForEach-Object {
        $file = Scoped-Path $_.FullName 'config\localconfig.vdf'
        if (Test-Path -LiteralPath $file) { Get-Item -LiteralPath $file }
    } | Sort-Object LastWriteTime -Descending)
    if (-not $configs.Count) { throw '未找到 Steam 的本地游戏设置，请先登录并从 Steam 启动游戏一次。' }
    return $configs[0].FullName
}
function Read-SteamOption([string]$SteamRoot, [string]$Config) {
    $root = Scoped-Path $SteamRoot 'userdata'
    $relative = [IO.Path]::GetFullPath($Config).Substring($root.Length + 1)
    $checked = Scoped-Path $root $relative
    if ($checked -ne [IO.Path]::GetFullPath($Config) -or $relative -notmatch '^\d+\\config\\localconfig\.vdf$') { throw 'Steam 设置路径校验失败。' }
    $source = [IO.File]::ReadAllText($checked, [Text.Encoding]::UTF8)
    return [AC8SteamVdf]::Get($source)
}
