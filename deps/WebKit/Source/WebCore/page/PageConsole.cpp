/*
 * Copyright (C) 2013 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Computer, Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "PageConsole.h"

#include "Chrome.h"
#include "ChromeClient.h"
#include "ConsoleAPITypes.h"
#include "ConsoleTypes.h"
#include "Document.h"
#include "Frame.h"
#include "InspectorConsoleInstrumentation.h"
#include "InspectorController.h"
#if !PLATFORM(JS)
#include "JSMainThreadExecState.h"
#endif
#include "Page.h"
#include "ScriptArguments.h"
#include "ScriptCallStack.h"
#include "ScriptCallStackFactory.h"
#include "ScriptableDocumentParser.h"
#include "Settings.h"
#include <bindings/ScriptValue.h>
#include <stdio.h>
#include <wtf/text/CString.h>
#include <wtf/text/WTFString.h>

namespace WebCore {

namespace {
    int muteCount = 0;
}

PageConsole::PageConsole(Page& page)
    : m_page(page)
{
}

PageConsole::~PageConsole()
{
}

void PageConsole::printSourceURLAndPosition(const String& sourceURL, unsigned lineNumber, unsigned columnNumber)
{
    if (!sourceURL.isEmpty()) {
        if (lineNumber > 0 && columnNumber > 0)
            printf("%s:%u:%u: ", sourceURL.utf8().data(), lineNumber, columnNumber);
        else
            printf("%s: ", sourceURL.utf8().data());
    }
}

void PageConsole::printMessageSourceAndLevelPrefix(MessageSource source, MessageLevel level)
{
    const char* sourceString;
    switch (source) {
    case XMLMessageSource:
        sourceString = "XML";
        break;
    case JSMessageSource:
        sourceString = "JS";
        break;
    case NetworkMessageSource:
        sourceString = "NETWORK";
        break;
    case ConsoleAPIMessageSource:
        sourceString = "CONSOLEAPI";
        break;
    case StorageMessageSource:
        sourceString = "STORAGE";
        break;
    case AppCacheMessageSource:
        sourceString = "APPCACHE";
        break;
    case RenderingMessageSource:
        sourceString = "RENDERING";
        break;
    case CSSMessageSource:
        sourceString = "CSS";
        break;
    case SecurityMessageSource:
        sourceString = "SECURITY";
        break;
    case OtherMessageSource:
        sourceString = "OTHER";
        break;
    default:
        ASSERT_NOT_REACHED();
        sourceString = "UNKNOWN";
        break;
    }

    const char* levelString;
    switch (level) {
    case DebugMessageLevel:
        levelString = "DEBUG";
        break;
    case LogMessageLevel:
        levelString = "LOG";
        break;
    case WarningMessageLevel:
        levelString = "WARN";
        break;
    case ErrorMessageLevel:
        levelString = "ERROR";
        break;
    default:
        ASSERT_NOT_REACHED();
        levelString = "UNKNOWN";
        break;
    }

    printf("%s %s:", sourceString, levelString);
}

void PageConsole::addMessage(MessageSource source, MessageLevel level, const String& message, unsigned long requestIdentifier, Document* document)
{
    String url;
    if (document)
        url = document->url().string();
    // FIXME: The below code attempts to determine line numbers for parser generated errors, but this is not the only reason why we can get here.
    // For example, if we are still parsing and get a WebSocket network error, it will be erroneously attributed to a line where parsing was paused.
    // Also, we should determine line numbers for script generated messages (e.g. calling getImageData on a canvas).
    // We probably need to split this function into multiple ones, as appropriate for different call sites. Or maybe decide based on MessageSource.
    // https://bugs.webkit.org/show_bug.cgi?id=125340
    unsigned line = 0;
    unsigned column = 0;
    if (document && document->parsing() && !document->isInDocumentWrite() && document->scriptableDocumentParser()) {
        ScriptableDocumentParser* parser = document->scriptableDocumentParser();
        if (!parser->isWaitingForScripts()
#if !PLATFORM(JS)
							&& !JSMainThreadExecState::currentState()
#endif
				) {
            TextPosition position = parser->textPosition();
            line = position.m_line.oneBasedInt();
            column = position.m_column.oneBasedInt();
        }
    }
    addMessage(source, level, message, url, line, column, 0, 0, requestIdentifier);
}

void PageConsole::addMessage(MessageSource source, MessageLevel level, const String& message, PassRefPtr<ScriptCallStack> callStack)
{
    addMessage(source, level, message, String(), 0, 0, callStack, 0);
}

void PageConsole::addMessage(MessageSource source, MessageLevel level, const String& message, const String& url, unsigned lineNumber, unsigned columnNumber, PassRefPtr<ScriptCallStack> callStack, JSC::ExecState* state, unsigned long requestIdentifier)
{
    if (muteCount && source != ConsoleAPIMessageSource)
        return;

    if (callStack)
        InspectorInstrumentation::addMessageToConsole(&m_page, source, LogMessageType, level, message, callStack, requestIdentifier);
    else
        InspectorInstrumentation::addMessageToConsole(&m_page, source, LogMessageType, level, message, url, lineNumber, columnNumber, state, requestIdentifier);

    if (source == CSSMessageSource)
        return;

    if (m_page.settings().privateBrowsingEnabled())
        return;

    m_page.chrome().client().addMessageToConsole(source, level, message, lineNumber, columnNumber, url);

    if (!m_page.settings().logsPageMessagesToSystemConsoleEnabled() && !shouldPrintExceptions())
        return;

    printSourceURLAndPosition(url, lineNumber, columnNumber);
    printMessageSourceAndLevelPrefix(source, level);

    printf(" %s\n", message.utf8().data());
}

// static
void PageConsole::mute()
{
    muteCount++;
}

// static
void PageConsole::unmute()
{
    ASSERT(muteCount > 0);
    muteCount--;
}

static bool printExceptions = false;

bool PageConsole::shouldPrintExceptions()
{
    return printExceptions;
}

void PageConsole::setShouldPrintExceptions(bool print)
{
    printExceptions = print;
}

} // namespace WebCore
