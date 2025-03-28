/*
 * Copyright (C) 2010 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "WebContext.h"

#import "PluginProcessManager.h"
#import "TextChecker.h"
#import "WKBrowsingContextControllerInternal.h"
#import "WKBrowsingContextControllerInternal.h"
#import "WebKitSystemInterface.h"
#import "WebProcessCreationParameters.h"
#import "WebProcessMessages.h"
#import "WindowServerConnection.h"
#if !PLATFORM(IOS)
#import <QuartzCore/CARemoteLayerServer.h>
#endif
#import <WebCore/Color.h>
#import <WebCore/FileSystem.h>
#import <WebCore/NotImplemented.h>
#import <WebCore/PlatformPasteboard.h>
#import <WebCore/SharedBuffer.h>
#import <sys/param.h>

#if ENABLE(NETWORK_PROCESS)
#import "NetworkProcessCreationParameters.h"
#import "NetworkProcessProxy.h"
#endif


#if PLATFORM(IOS) || __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090

#if __has_include(<CFNetwork/CFURLProtocolPriv.h>)
#include <CFNetwork/CFURLProtocolPriv.h>
#else
extern "C" Boolean _CFNetworkIsKnownHSTSHostWithSession(CFURLRef url, CFURLStorageSessionRef session);
extern "C" void _CFNetworkResetHSTSHostsWithSession(CFURLStorageSessionRef session);
#endif

#endif

using namespace WebCore;

NSString *WebDatabaseDirectoryDefaultsKey = @"WebDatabaseDirectory";
NSString *WebKitLocalCacheDefaultsKey = @"WebKitLocalCache";
NSString *WebStorageDirectoryDefaultsKey = @"WebKitLocalStorageDatabasePathPreferenceKey";
NSString *WebKitKerningAndLigaturesEnabledByDefaultDefaultsKey = @"WebKitKerningAndLigaturesEnabledByDefault";

#if !PLATFORM(IOS)
static NSString *WebKitApplicationDidChangeAccessibilityEnhancedUserInterfaceNotification = @"NSApplicationDidChangeAccessibilityEnhancedUserInterfaceNotification";
#endif

// FIXME: <rdar://problem/9138817> - After this "backwards compatibility" radar is removed, this code should be removed to only return an empty String.
NSString *WebIconDatabaseDirectoryDefaultsKey = @"WebIconDatabaseDirectoryDefaultsKey";

#if ENABLE(NETWORK_PROCESS)
static NSString * const WebKit2HTTPProxyDefaultsKey = @"WebKit2HTTPProxy";
static NSString * const WebKit2HTTPSProxyDefaultsKey = @"WebKit2HTTPSProxy";
#endif

namespace WebKit {

NSString *SchemeForCustomProtocolRegisteredNotificationName = @"WebKitSchemeForCustomProtocolRegisteredNotification";
NSString *SchemeForCustomProtocolUnregisteredNotificationName = @"WebKitSchemeForCustomProtocolUnregisteredNotification";

static void registerUserDefaultsIfNeeded()
{
    static bool didRegister;
    if (didRegister)
        return;

    didRegister = true;
    NSMutableDictionary *registrationDictionary = [NSMutableDictionary dictionary];
    
#if PLATFORM(IOS) || __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    [registrationDictionary setObject:[NSNumber numberWithBool:YES] forKey:WebKitKerningAndLigaturesEnabledByDefaultDefaultsKey];
#endif

    [[NSUserDefaults standardUserDefaults] registerDefaults:registrationDictionary];
}

void WebContext::updateProcessSuppressionState() const
{
#if ENABLE(NETWORK_PROCESS)
    if (m_usesNetworkProcess && m_networkProcess)
        m_networkProcess->setProcessSuppressionEnabled(processSuppressionEnabled());
#endif
#if ENABLE(NETSCAPE_PLUGIN_API)
    PluginProcessManager::shared().setProcessSuppressionEnabled(processSuppressionIsEnabledForAllContexts());
#endif
}

void WebContext::platformInitialize()
{
    registerUserDefaultsIfNeeded();
    registerNotificationObservers();
}

String WebContext::platformDefaultApplicationCacheDirectory() const
{
    NSString *appName = [[NSBundle mainBundle] bundleIdentifier];
    if (!appName)
        appName = [[NSProcessInfo processInfo] processName];

    ASSERT(appName);

    char cacheDirectory[MAXPATHLEN];
    size_t cacheDirectoryLen = confstr(_CS_DARWIN_USER_CACHE_DIR, cacheDirectory, MAXPATHLEN);
    if (!cacheDirectoryLen)
        return String();

    NSString *cacheDir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:cacheDirectory length:cacheDirectoryLen - 1];
    return [cacheDir stringByAppendingPathComponent:appName];
}

void WebContext::platformInitializeWebProcess(WebProcessCreationParameters& parameters)
{
    parameters.presenterApplicationPid = getpid();

#if PLATFORM(MAC) && !PLATFORM(IOS)
    parameters.accessibilityEnhancedUserInterfaceEnabled = [[NSApp accessibilityAttributeValue:@"AXEnhancedUserInterface"] boolValue];
#else
    parameters.accessibilityEnhancedUserInterfaceEnabled = false;
#endif

    NSURLCache *urlCache = [NSURLCache sharedURLCache];
    parameters.nsURLCacheMemoryCapacity = [urlCache memoryCapacity];
    parameters.nsURLCacheDiskCapacity = [urlCache diskCapacity];

#if !PLATFORM(IOS) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    parameters.shouldForceScreenFontSubstitution = [[NSUserDefaults standardUserDefaults] boolForKey:@"NSFontDefaultScreenFontSubstitutionEnabled"];
#endif
    parameters.shouldEnableKerningAndLigaturesByDefault = [[NSUserDefaults standardUserDefaults] boolForKey:WebKitKerningAndLigaturesEnabledByDefaultDefaultsKey];

#if USE(ACCELERATED_COMPOSITING) && HAVE(HOSTED_CORE_ANIMATION)
#if !PLATFORM(IOS)
    mach_port_t renderServerPort = [[CARemoteLayerServer sharedServer] serverPort];
    if (renderServerPort != MACH_PORT_NULL)
        parameters.acceleratedCompositingPort = IPC::MachPort(renderServerPort, MACH_MSG_TYPE_COPY_SEND);
#endif
#endif

    // FIXME: This should really be configurable; we shouldn't just blindly allow read access to the UI process bundle.
    parameters.uiProcessBundleResourcePath = [[NSBundle mainBundle] resourcePath];
    SandboxExtension::createHandle(parameters.uiProcessBundleResourcePath, SandboxExtension::ReadOnly, parameters.uiProcessBundleResourcePathExtensionHandle);

    parameters.uiProcessBundleIdentifier = String([[NSBundle mainBundle] bundleIdentifier]);

#if ENABLE(NETWORK_PROCESS)
    if (!m_usesNetworkProcess) {
#endif
#if ENABLE(CUSTOM_PROTOCOLS)
        for (const auto& scheme : globalURLSchemesWithCustomProtocolHandlers())
            parameters.urlSchemesRegisteredForCustomProtocols.append(scheme);
#endif
#if ENABLE(NETWORK_PROCESS)
    }
#endif
}

#if ENABLE(NETWORK_PROCESS)
void WebContext::platformInitializeNetworkProcess(NetworkProcessCreationParameters& parameters)
{
    NSURLCache *urlCache = [NSURLCache sharedURLCache];
    parameters.nsURLCacheMemoryCapacity = [urlCache memoryCapacity];
    parameters.nsURLCacheDiskCapacity = [urlCache diskCapacity];

    parameters.parentProcessName = [[NSProcessInfo processInfo] processName];
    parameters.uiProcessBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];

#if ENABLE(CUSTOM_PROTOCOLS)
    for (const auto& scheme : globalURLSchemesWithCustomProtocolHandlers())
        parameters.urlSchemesRegisteredForCustomProtocols.append(scheme);
#endif

    parameters.httpProxy = [[NSUserDefaults standardUserDefaults] stringForKey:WebKit2HTTPProxyDefaultsKey];
    parameters.httpsProxy = [[NSUserDefaults standardUserDefaults] stringForKey:WebKit2HTTPSProxyDefaultsKey];
}
#endif

void WebContext::platformInvalidateContext()
{
    unregisterNotificationObservers();
}

String WebContext::platformDefaultDiskCacheDirectory() const
{
    RetainPtr<NSString> cachePath = adoptNS((NSString *)WKCopyFoundationCacheDirectory());
    if (!cachePath)
        cachePath = @"~/Library/Caches/com.apple.WebKit2.WebProcess";

    return [cachePath.get() stringByStandardizingPath];
}

String WebContext::platformDefaultCookieStorageDirectory() const
{
    notImplemented();
    return [@"" stringByStandardizingPath];
}

String WebContext::platformDefaultDatabaseDirectory() const
{
    NSString *databasesDirectory = [[NSUserDefaults standardUserDefaults] objectForKey:WebDatabaseDirectoryDefaultsKey];
    if (!databasesDirectory || ![databasesDirectory isKindOfClass:[NSString class]])
        databasesDirectory = @"~/Library/WebKit/Databases";
    return [databasesDirectory stringByStandardizingPath];
}

String WebContext::platformDefaultIconDatabasePath() const
{
    // FIXME: <rdar://problem/9138817> - After this "backwards compatibility" radar is removed, this code should be removed to only return an empty String.
    NSString *databasesDirectory = [[NSUserDefaults standardUserDefaults] objectForKey:WebIconDatabaseDirectoryDefaultsKey];
    if (!databasesDirectory || ![databasesDirectory isKindOfClass:[NSString class]])
        databasesDirectory = @"~/Library/Icons/WebpageIcons.db";
    return [databasesDirectory stringByStandardizingPath];
}

String WebContext::platformDefaultLocalStorageDirectory() const
{
    NSString *localStorageDirectory = [[NSUserDefaults standardUserDefaults] objectForKey:WebStorageDirectoryDefaultsKey];
    if (!localStorageDirectory || ![localStorageDirectory isKindOfClass:[NSString class]])
        localStorageDirectory = @"~/Library/WebKit/LocalStorage";
    return [localStorageDirectory stringByStandardizingPath];
}

bool WebContext::omitPDFSupport()
{
    // Since this is a "secret default" we don't bother registering it.
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"WebKitOmitPDFSupport"];
}

void WebContext::getPasteboardTypes(const String& pasteboardName, Vector<String>& pasteboardTypes)
{
    PlatformPasteboard(pasteboardName).getTypes(pasteboardTypes);
}

void WebContext::getPasteboardPathnamesForType(const String& pasteboardName, const String& pasteboardType, Vector<String>& pathnames)
{
    PlatformPasteboard(pasteboardName).getPathnamesForType(pathnames, pasteboardType);
}

void WebContext::getPasteboardStringForType(const String& pasteboardName, const String& pasteboardType, String& string)
{
    string = PlatformPasteboard(pasteboardName).stringForType(pasteboardType);
}

void WebContext::getPasteboardBufferForType(const String& pasteboardName, const String& pasteboardType, SharedMemory::Handle& handle, uint64_t& size)
{
    RefPtr<SharedBuffer> buffer = PlatformPasteboard(pasteboardName).bufferForType(pasteboardType);
    if (!buffer)
        return;
    size = buffer->size();
    RefPtr<SharedMemory> sharedMemoryBuffer = SharedMemory::create(size);
    memcpy(sharedMemoryBuffer->data(), buffer->data(), size);
    sharedMemoryBuffer->createHandle(handle, SharedMemory::ReadOnly);
}

void WebContext::pasteboardCopy(const String& fromPasteboard, const String& toPasteboard, uint64_t& newChangeCount)
{
    newChangeCount = PlatformPasteboard(toPasteboard).copy(fromPasteboard);
}

void WebContext::getPasteboardChangeCount(const String& pasteboardName, uint64_t& changeCount)
{
    changeCount = PlatformPasteboard(pasteboardName).changeCount();
}

void WebContext::getPasteboardUniqueName(String& pasteboardName)
{
    pasteboardName = PlatformPasteboard::uniqueName();
}

void WebContext::getPasteboardColor(const String& pasteboardName, WebCore::Color& color)
{
    color = PlatformPasteboard(pasteboardName).color();    
}

void WebContext::getPasteboardURL(const String& pasteboardName, WTF::String& urlString)
{
    urlString = PlatformPasteboard(pasteboardName).url().string();
}

void WebContext::addPasteboardTypes(const String& pasteboardName, const Vector<String>& pasteboardTypes, uint64_t& newChangeCount)
{
    newChangeCount = PlatformPasteboard(pasteboardName).addTypes(pasteboardTypes);
}

void WebContext::setPasteboardTypes(const String& pasteboardName, const Vector<String>& pasteboardTypes, uint64_t& newChangeCount)
{
    newChangeCount = PlatformPasteboard(pasteboardName).setTypes(pasteboardTypes);
}

void WebContext::setPasteboardPathnamesForType(const String& pasteboardName, const String& pasteboardType, const Vector<String>& pathnames, uint64_t& newChangeCount)
{
    newChangeCount = PlatformPasteboard(pasteboardName).setPathnamesForType(pathnames, pasteboardType);
}

void WebContext::setPasteboardStringForType(const String& pasteboardName, const String& pasteboardType, const String& string, uint64_t& newChangeCount)
{
    newChangeCount = PlatformPasteboard(pasteboardName).setStringForType(string, pasteboardType);
}

void WebContext::setPasteboardBufferForType(const String& pasteboardName, const String& pasteboardType, const SharedMemory::Handle& handle, uint64_t size, uint64_t& newChangeCount)
{
    if (handle.isNull()) {
        newChangeCount = PlatformPasteboard(pasteboardName).setBufferForType(0, pasteboardType);
        return;
    }
    RefPtr<SharedMemory> sharedMemoryBuffer = SharedMemory::create(handle, SharedMemory::ReadOnly);
    RefPtr<SharedBuffer> buffer = SharedBuffer::create(static_cast<unsigned char *>(sharedMemoryBuffer->data()), size);
    newChangeCount = PlatformPasteboard(pasteboardName).setBufferForType(buffer, pasteboardType);
}

#if PLATFORM(IOS)
void WebContext::writeWebContentToPasteboard(const WebCore::PasteboardWebContent& content)
{
    PlatformPasteboard().write(content);
}

void WebContext::writeImageToPasteboard(const WebCore::PasteboardImage& pasteboardImage)
{
    PlatformPasteboard().write(pasteboardImage);
}

void WebContext::writeStringToPasteboard(const String& pasteboardType, const String& text)
{
    PlatformPasteboard().write(pasteboardType, text);
}

void WebContext::readStringFromPasteboard(uint64_t index, const String& pasteboardType, WTF::String& value)
{
    value = PlatformPasteboard().readString(index, pasteboardType);
}

void WebContext::readURLFromPasteboard(uint64_t index, const String& pasteboardType, String& url)
{
    url = PlatformPasteboard().readURL(index, pasteboardType);
}

void WebContext::readBufferFromPasteboard(uint64_t index, const String& pasteboardType, SharedMemory::Handle& handle, uint64_t& size)
{
    RefPtr<SharedBuffer> buffer = PlatformPasteboard().readBuffer(index, pasteboardType);
    if (!buffer)
        return;
    size = buffer->size();
    RefPtr<SharedMemory> sharedMemoryBuffer = SharedMemory::create(size);
    memcpy(sharedMemoryBuffer->data(), buffer->data(), size);
    sharedMemoryBuffer->createHandle(handle, SharedMemory::ReadOnly);
}

void WebContext::getPasteboardItemsCount(uint64_t& itemsCount)
{
    itemsCount = PlatformPasteboard().count();
}

#endif

bool WebContext::processSuppressionEnabled() const
{
    for (const auto& process : m_processes) {
        if (!process->allPagesAreProcessSuppressible())
            return false;
    }
    return true;
}

bool WebContext::processSuppressionIsEnabledForAllContexts()
{
    for (const auto* context : WebContext::allContexts()) {
        if (!context->processSuppressionEnabled())
            return false;
    }
    return true;
}

void WebContext::registerNotificationObservers()
{
#if !PLATFORM(IOS)
    // Listen for enhanced accessibility changes and propagate them to the WebProcess.
    m_enhancedAccessibilityObserver = [[NSNotificationCenter defaultCenter] addObserverForName:WebKitApplicationDidChangeAccessibilityEnhancedUserInterfaceNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        setEnhancedAccessibility([[[note userInfo] objectForKey:@"AXEnhancedUserInterface"] boolValue]);
    }];

    m_automaticTextReplacementNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSpellCheckerDidChangeAutomaticTextReplacementNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *notification) {
        TextChecker::didChangeAutomaticTextReplacementEnabled();
        textCheckerStateChanged();
    }];
    
    m_automaticSpellingCorrectionNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSpellCheckerDidChangeAutomaticSpellingCorrectionNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *notification) {
        TextChecker::didChangeAutomaticSpellingCorrectionEnabled();
        textCheckerStateChanged();
    }];

#if __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    m_automaticQuoteSubstitutionNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSpellCheckerDidChangeAutomaticQuoteSubstitutionNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *notification) {
        TextChecker::didChangeAutomaticQuoteSubstitutionEnabled();
        textCheckerStateChanged();
    }];

    m_automaticDashSubstitutionNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSpellCheckerDidChangeAutomaticDashSubstitutionNotification object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *notification) {
        TextChecker::didChangeAutomaticDashSubstitutionEnabled();
        textCheckerStateChanged();
    }];
#endif
#endif // !PLATFORM(IOS)
}

void WebContext::unregisterNotificationObservers()
{
#if !PLATFORM(IOS)
    [[NSNotificationCenter defaultCenter] removeObserver:m_enhancedAccessibilityObserver.get()];    
    [[NSNotificationCenter defaultCenter] removeObserver:m_automaticTextReplacementNotificationObserver.get()];
    [[NSNotificationCenter defaultCenter] removeObserver:m_automaticSpellingCorrectionNotificationObserver.get()];
#if __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    [[NSNotificationCenter defaultCenter] removeObserver:m_automaticQuoteSubstitutionNotificationObserver.get()];
    [[NSNotificationCenter defaultCenter] removeObserver:m_automaticDashSubstitutionNotificationObserver.get()];
#endif
#endif // !PLATFORM(IOS)
}

#if PLATFORM(IOS) || __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
static CFURLStorageSessionRef privateBrowsingSession()
{
    static CFURLStorageSessionRef session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *identifier = [NSString stringWithFormat:@"%@.PrivateBrowsing", [[NSBundle mainBundle] bundleIdentifier]];

        session = WKCreatePrivateStorageSession((CFStringRef)identifier);
    });

    return session;
}
#endif

bool WebContext::isURLKnownHSTSHost(const String& urlString, bool privateBrowsingEnabled) const
{
#if PLATFORM(IOS) || __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    RetainPtr<CFURLRef> url = URL(URL(), urlString).createCFURL();

    return _CFNetworkIsKnownHSTSHostWithSession(url.get(), privateBrowsingEnabled ? privateBrowsingSession() : nullptr);
#else
    return false;
#endif
}

void WebContext::resetHSTSHosts()
{
#if PLATFORM(IOS) || __MAC_OS_X_VERSION_MIN_REQUIRED >= 1090
    _CFNetworkResetHSTSHostsWithSession(nullptr);
    _CFNetworkResetHSTSHostsWithSession(privateBrowsingSession());
#endif
}

} // namespace WebKit
