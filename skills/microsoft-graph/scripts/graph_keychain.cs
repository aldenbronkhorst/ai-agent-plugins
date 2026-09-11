using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

// The OS owns encryption and access control. No token crosses a process boundary.
public static class AgentGraphKeychain
{
    private const string Security = "/System/Library/Frameworks/Security.framework/Security";
    private const string CoreFoundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const string LocalAuthentication = "/System/Library/Frameworks/LocalAuthentication.framework/LocalAuthentication";
    [DllImport("/usr/lib/libobjc.A.dylib")] private static extern IntPtr objc_getClass(string name);
    [DllImport("/usr/lib/libobjc.A.dylib")] private static extern IntPtr sel_registerName(string name);
    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_msgSend")] private static extern IntPtr Send(IntPtr receiver, IntPtr selector);
    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint="objc_msgSend")] private static extern void SendBool(IntPtr receiver, IntPtr selector, [MarshalAs(UnmanagedType.I1)] bool value);
    [DllImport(Security)] private static extern int SecItemCopyMatching(IntPtr query, out IntPtr result);
    [DllImport(Security)] private static extern int SecItemUpdate(IntPtr query, IntPtr attributes);
    [DllImport(Security)] private static extern int SecItemAdd(IntPtr attributes, IntPtr result);
    [DllImport(CoreFoundation)] private static extern IntPtr CFDictionaryCreateMutable(IntPtr allocator, nint capacity, IntPtr keys, IntPtr values);
    [DllImport(CoreFoundation)] private static extern void CFDictionarySetValue(IntPtr dictionary, IntPtr key, IntPtr value);
    [DllImport(CoreFoundation)] private static extern IntPtr CFStringCreateWithCString(IntPtr allocator, string value, uint encoding);
    [DllImport(CoreFoundation)] private static extern IntPtr CFDataCreate(IntPtr allocator, byte[] bytes, nint length);
    [DllImport(CoreFoundation)] private static extern nint CFDataGetLength(IntPtr data);
    [DllImport(CoreFoundation)] private static extern IntPtr CFDataGetBytePtr(IntPtr data);
    [DllImport(CoreFoundation)] private static extern void CFRelease(IntPtr value);

    private static IntPtr Constant(IntPtr library, string name) => Marshal.ReadIntPtr(NativeLibrary.GetExport(library, name));

    public static string Access(string serviceName, string accountName, string replacement)
    {
        var owned = new List<IntPtr>();
        IntPtr data = IntPtr.Zero, security = IntPtr.Zero, foundation = IntPtr.Zero, localAuth = IntPtr.Zero, authContext = IntPtr.Zero;
        byte[] secret = null;
        try
        {
            security = NativeLibrary.Load(Security);
            foundation = NativeLibrary.Load(CoreFoundation);
            localAuth = NativeLibrary.Load(LocalAuthentication);
            var query = CFDictionaryCreateMutable(IntPtr.Zero, 0, IntPtr.Zero, IntPtr.Zero);
            owned.Add(query);
            var service = CFStringCreateWithCString(IntPtr.Zero, serviceName, 0x08000100);
            var account = CFStringCreateWithCString(IntPtr.Zero, accountName, 0x08000100);
            owned.Add(service); owned.Add(account);
            CFDictionarySetValue(query, Constant(security, "kSecClass"), Constant(security, "kSecClassGenericPassword"));
            CFDictionarySetValue(query, Constant(security, "kSecAttrService"), service);
            CFDictionarySetValue(query, Constant(security, "kSecAttrAccount"), account);
            // Use the current per-query LAContext policy, not deprecated global
            // interaction switches or kSecUseAuthenticationUI flags.
            authContext = Send(Send(objc_getClass("LAContext"), sel_registerName("alloc")), sel_registerName("init"));
            if (authContext == IntPtr.Zero) throw new InvalidOperationException("Local Authentication is unavailable.");
            SendBool(authContext, sel_registerName("setInteractionNotAllowed:"), true);
            CFDictionarySetValue(query, Constant(security, "kSecUseAuthenticationContext"), authContext);
            if (replacement == null)
            {
                CFDictionarySetValue(query, Constant(security, "kSecReturnData"), Constant(foundation, "kCFBooleanTrue"));
                var status = SecItemCopyMatching(query, out data);
                if (status == -25300) return null;
                Check(status);
                secret = new byte[checked((int)CFDataGetLength(data))];
                Marshal.Copy(CFDataGetBytePtr(data), secret, 0, secret.Length);
                return Encoding.UTF8.GetString(secret);
            }
            secret = Encoding.UTF8.GetBytes(replacement);
            var value = CFDataCreate(IntPtr.Zero, secret, secret.Length);
            var updates = CFDictionaryCreateMutable(IntPtr.Zero, 0, IntPtr.Zero, IntPtr.Zero);
            owned.Add(value); owned.Add(updates);
            CFDictionarySetValue(updates, Constant(security, "kSecValueData"), value);
            var updated = SecItemUpdate(query, updates);
            if (updated == -25300)
            {
                CFDictionarySetValue(query, Constant(security, "kSecValueData"), value);
                Check(SecItemAdd(query, IntPtr.Zero));
            }
            else Check(updated);
            return null;
        }
        finally
        {
            if (secret != null) Array.Clear(secret, 0, secret.Length);
            if (data != IntPtr.Zero) CFRelease(data);
            foreach (var value in owned) if (value != IntPtr.Zero) CFRelease(value);
            if (authContext != IntPtr.Zero) Send(authContext, sel_registerName("release"));
            if (localAuth != IntPtr.Zero) NativeLibrary.Free(localAuth);
            if (foundation != IntPtr.Zero) NativeLibrary.Free(foundation);
            if (security != IntPtr.Zero) NativeLibrary.Free(security);
        }
    }

    private static void Check(int status)
    {
        if (status != 0) throw new InvalidOperationException(
            "Microsoft Graph Keychain access failed (OSStatus " + status + "). Unlock or repair the local keychain before retrying; no new sign-in was started by the store.");
    }
}
