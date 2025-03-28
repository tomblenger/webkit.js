/*
 * Copyright (c) 2006, 2007, 2008, 2009 Google Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#if PLATFORM(JS)
#include "DebuggerJS.h"
#include "Font.h"
#include "FontCache.h"
#include "FontDescription.h"
#include "SimpleFontData.h"
#else
#include <unicode/locid.h>
#include "core/platform/NotImplemented.h"
#include "core/platform/graphics/Font.h"
#include "core/platform/graphics/FontCache.h"
#include "core/platform/graphics/FontDescription.h"
#include "core/platform/graphics/SimpleFontData.h"
#endif
#include "SkTypeface.h"
#include "wtf/Assertions.h"
#include "wtf/text/AtomicString.h"
#include "wtf/text/CString.h"

namespace WebCore {

void FontCache::platformInit()
{
}

PassRefPtr<SimpleFontData> FontCache::getFontDataForCharacter(const Font& font, UChar32 c)
{
    icu::Locale locale = icu::Locale::getDefault();
    FontCache::SimpleFontFamily family;
    FontCache::getFontFamilyForCharacter(c, locale.getLanguage(), &family);
    if (family.name.isEmpty())
        return 0;

    AtomicString atomicFamily(family.name);
    // Changes weight and/or italic of given FontDescription depends on
    // the result of fontconfig so that keeping the correct font mapping
    // of the given character. See http://crbug.com/32109 for details.
    bool shouldSetFakeBold = false;
    bool shouldSetFakeItalic = false;
    FontDescription description(font.fontDescription());
    if (family.isBold && description.weight() < FontWeightBold)
        description.setWeight(FontWeightBold);
    if (!family.isBold && description.weight() >= FontWeightBold) {
        shouldSetFakeBold = true;
        description.setWeight(FontWeightNormal);
    }
    if (family.isItalic && description.italic() == FontItalicOff)
        description.setItalic(FontItalicOn);
    if (!family.isItalic && description.italic() == FontItalicOn) {
        shouldSetFakeItalic = true;
        description.setItalic(FontItalicOff);
    }

    FontPlatformData* substitutePlatformData = getFontResourcePlatformData(description, atomicFamily, DoNotRetain);
    if (!substitutePlatformData)
        return 0;
    FontPlatformData platformData = FontPlatformData(*substitutePlatformData);
    platformData.setFakeBold(shouldSetFakeBold);
    platformData.setFakeItalic(shouldSetFakeItalic);
    return getFontResourceData(&platformData, DoNotRetain);
}

PassRefPtr<SimpleFontData> FontCache::getSimilarFontPlatformData(const Font& font)
{
    return 0;
}

PassRefPtr<SimpleFontData> FontCache::getLastResortFallbackFont(const FontDescription& description, ShouldRetain shouldRetain)
{
    const FontPlatformData* fontPlatformData = getFallbackFontData(description);
    if (!fontPlatformData) {
        // we should at least have Arial; this is the SkFontHost_fontconfig last resort fallback
        DEFINE_STATIC_LOCAL(const AtomicString, arialStr, ("Arial", AtomicString::ConstructFromLiteral));
        fontPlatformData = getFontResourcePlatformData(description, arialStr);
    }

    ASSERT(fontPlatformData);
    return getFontResourceData(fontPlatformData, shouldRetain);
}

void FontCache::getTraitsInFamily(const AtomicString& familyName,
                                  Vector<unsigned>& traitsMasks)
{
    notImplemented();
}

FontPlatformData* FontCache::createFontPlatformData(const FontDescription& fontDescription,
                                                    const AtomicString& family)
{
    const char* name = 0;
    CString s;

    // If we're creating a fallback font (e.g. "-webkit-monospace"), convert the name into
    // the fallback name (like "monospace") that fontconfig understands.
    if (!family.length() || family.startsWith("-webkit-")) {
        static const struct {
            FontDescription::GenericFamilyType mType;
            const char* mName;
        } fontDescriptions[] = {
            { FontDescription::SerifFamily, "serif" },
            { FontDescription::SansSerifFamily, "sans-serif" },
            { FontDescription::MonospaceFamily, "monospace" },
            { FontDescription::CursiveFamily, "cursive" },
            { FontDescription::FantasyFamily, "fantasy" }
        };

        FontDescription::GenericFamilyType type = fontDescription.genericFamily();
        for (unsigned i = 0; i < SK_ARRAY_COUNT(fontDescriptions); i++) {
            if (type == fontDescriptions[i].mType) {
                name = fontDescriptions[i].mName;
                break;
            }
        }
        if (!name)
            name = "";
    } else {
        // convert the name to utf8
        s = family.string().utf8();
        name = s.data();
    }

    int style = SkTypeface::kNormal;
    if (fontDescription.weight() >= FontWeightBold)
        style |= SkTypeface::kBold;
    if (fontDescription.italic())
        style |= SkTypeface::kItalic;

    SkTypeface* tf = SkTypeface::CreateFromName(name, static_cast<SkTypeface::Style>(style));
    if (!tf)
        return 0;

    FontPlatformData* result =
        new FontPlatformData(tf,
                             name,
                             fontDescription.computedSize(),
                             (style & SkTypeface::kBold) && !tf->isBold(),
                             (style & SkTypeface::kItalic) && !tf->isItalic(),
                             fontDescription.orientation());
    tf->unref();
    return result;
}

} // namespace WebCore
