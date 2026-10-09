using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class AC8TextTables {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr handle, IntPtr address, byte[] buffer, UIntPtr length, out UIntPtr copied);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr handle, IntPtr address, byte[] buffer, UIntPtr length, out UIntPtr copied);
    class FString {
        public long Pointer; public int Count; public int Capacity; public string Text;
    }
    class Pending {
        public long Address; public FString Original; public byte[] Bytes; public string After; public string Key;
    }
    public class Result {
        public int Modified; public int AlreadyTranslated; public int Eligible;
        public string[] Skipped; public int Tables;
    }
    static byte[] Read(IntPtr handle, long address, int length) {
        byte[] bytes=new byte[length]; UIntPtr copied;
        if(!ReadProcessMemory(handle,new IntPtr(address),bytes,new UIntPtr((uint)length),out copied) || copied.ToUInt64()!=(ulong)length)
            throw new InvalidOperationException("Cannot read game text memory: "+Marshal.GetLastWin32Error());
        return bytes;
    }
    static void Write(IntPtr handle, long address, byte[] bytes) {
        UIntPtr copied;
        if(!WriteProcessMemory(handle,new IntPtr(address),bytes,new UIntPtr((uint)bytes.Length),out copied) || copied.ToUInt64()!=(ulong)bytes.Length)
            throw new InvalidOperationException("Cannot write game text memory: "+Marshal.GetLastWin32Error());
    }
    static FString StringAt(IntPtr handle,long address) {
        byte[] data=Read(handle,address,16);
        var result=new FString {Pointer=BitConverter.ToInt64(data,0),Count=BitConverter.ToInt32(data,8),Capacity=BitConverter.ToInt32(data,12)};
        if(result.Pointer<=0 || result.Count<1 || result.Count>4096 || result.Capacity<result.Count || result.Capacity>65536)
            throw new InvalidOperationException("Unexpected FString bounds");
        string value=new UnicodeEncoding(false,false,true).GetString(Read(handle,result.Pointer,result.Count*2));
        if(value[value.Length-1]!='\0' || value.Substring(0,value.Length-1).Contains("\0"))
            throw new InvalidOperationException("Unexpected FString termination");
        result.Text=value.Substring(0,value.Length-1); return result;
    }
    static long[] Tables(IntPtr handle,long moduleBase) {
        var tables=new List<long>();
        foreach(int offset in new[]{0x50,0xa0}) {
            byte[] map=Read(handle,moduleBase+0xe511bc0L+offset,12);
            long data=BitConverter.ToInt64(map,0); int count=BitConverter.ToInt32(map,8);
            if(data<=0 || count!=2) throw new InvalidOperationException("Localization maps not initialized");
            for(int i=0;i<count;i++) {
                long entry=data+i*40; string key=StringAt(handle,entry).Text;
                byte[] array=Read(handle,entry+16,16);
                long pointer=BitConverter.ToInt64(array,0);int length=BitConverter.ToInt32(array,8),capacity=BitConverter.ToInt32(array,12);
                if(key=="CP_" && pointer>0 && length==46584 && capacity>=length && StringAt(handle,pointer).Text=="喂喂，听见没？") tables.Add(pointer);
            }
        }
        if(tables.Count!=2 || tables.Distinct().Count()!=2) throw new InvalidOperationException("Expected two CP_ text tables");
        return tables.ToArray();
    }
    static void Offline(int pid) {
        foreach(var p in Process.GetProcesses()) {
            using(p) {
                string name;
                try {name=p.ProcessName.ToLowerInvariant();} catch(InvalidOperationException) {continue;}
                if(name.Contains("easyanticheat") || name.Contains("start_protected_game")) throw new InvalidOperationException("Protected game launcher detected");
            }
        }
        using(var p=Process.GetProcessById(pid)) if(p.ProcessName!="AceCombat8") throw new InvalidOperationException("Game PID mismatch");
    }
    public static Result Patch(int pid,long moduleBase,int[] indices,string[] before,string[] after,string[] keys,bool apply) {
        Offline(pid);
        if(indices.Length!=before.Length || indices.Length!=after.Length || indices.Length!=keys.Length) throw new InvalidOperationException("Translation array mismatch");
        IntPtr handle=OpenProcess(apply ? 0x38u : 0x10u,false,pid);
        if(handle==IntPtr.Zero) throw new InvalidOperationException("Cannot open offline game: "+Marshal.GetLastWin32Error());
        try {
            long[] tables=null; Stopwatch timer=Stopwatch.StartNew();
            while(tables==null) {
                try {tables=Tables(handle,moduleBase);} catch(InvalidOperationException) { if(timer.Elapsed.TotalSeconds>=30) throw; Thread.Sleep(100); }
            }
            var result=new Result {Tables=tables.Length};
            var skipped=new List<string>(); var pending=new List<Pending>();
            foreach(long table in tables) for(int i=0;i<indices.Length;i++) {
                if(indices[i]<0 || indices[i]>=46584 || String.IsNullOrEmpty(after[i]) || after[i].Contains("\0")) throw new InvalidOperationException("Invalid translation row");
                long address=table+indices[i]*16L; FString current=StringAt(handle,address);
                if(current.Text==after[i]) {result.AlreadyTranslated++;continue;}
                if(current.Text!=before[i]) {skipped.Add(keys[i]+": source mismatch");continue;}
                if(after[i].Length+1>current.Capacity) {skipped.Add(keys[i]+": allocation too small");continue;}
                pending.Add(new Pending {Address=address,Original=current,Bytes=Encoding.Unicode.GetBytes(after[i]+"\0"),After=after[i],Key=keys[i]});
            }
            if(apply) {
                Offline(pid);
                if(!Tables(handle,moduleBase).SequenceEqual(tables)) throw new InvalidOperationException("Text tables changed during validation");
                foreach(var item in pending) {
                    FString current=StringAt(handle,item.Address),old=item.Original;
                    if(current.Pointer!=old.Pointer || current.Count!=old.Count || current.Capacity!=old.Capacity || current.Text!=old.Text)
                        throw new InvalidOperationException("Text changed during validation");
                    Write(handle,current.Pointer,item.Bytes);
                    Write(handle,item.Address+8,BitConverter.GetBytes(item.After.Length+1));
                    if(StringAt(handle,item.Address).Text!=item.After) throw new InvalidOperationException("Text readback failed");
                    result.Modified++;
                }
            } else {result.Eligible=pending.Count;}
            result.Skipped=skipped.ToArray(); return result;
        } finally {CloseHandle(handle);}
    }
}
