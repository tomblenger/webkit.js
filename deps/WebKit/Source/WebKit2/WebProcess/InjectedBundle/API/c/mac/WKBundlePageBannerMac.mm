/*
 * Copyright (C) 2013 Apple Inc. All rights reserved.
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

#include "config.h"
#include "WKBundlePageBannerMac.h"

#include "APIClient.h"
#include "PageBanner.h"
#include "WKAPICast.h"
#include "WKBundleAPICast.h"
#include <wtf/PassOwnPtr.h>

using namespace WebCore;
using namespace WebKit;

namespace API {
template<> struct ClientTraits<WKBundlePageBannerClientBase> {
    typedef std::tuple<WKBundlePageBannerClientV0> Versions;
};
}

class PageBannerClientImpl : API::Client<WKBundlePageBannerClientBase>, public PageBanner::Client {
public:
    explicit PageBannerClientImpl(WKBundlePageBannerClientBase* client)
    {
        initialize(client);
    }

    virtual ~PageBannerClientImpl()
    {
    }

private:
    // PageBanner::Client.
    virtual void pageBannerDestroyed(PageBanner*) OVERRIDE
    {
        delete this;
    }
    
    virtual bool mouseEvent(PageBanner* pageBanner, WebEvent::Type type, WebMouseEvent::Button button, const IntPoint& position) OVERRIDE
    {
        switch (type) {
        case WebEvent::MouseDown: {
            if (!m_client.mouseDown)
                return false;

            return m_client.mouseDown(toAPI(pageBanner), toAPI(position), toAPI(button), m_client.base.clientInfo);
        }
        case WebEvent::MouseUp: {
            if (!m_client.mouseUp)
                return false;

            return m_client.mouseUp(toAPI(pageBanner), toAPI(position), toAPI(button), m_client.base.clientInfo);
        }
        case WebEvent::MouseMove: {
            if (button == WebMouseEvent::NoButton) {
                if (!m_client.mouseMoved)
                    return false;

                return m_client.mouseMoved(toAPI(pageBanner), toAPI(position), m_client.base.clientInfo);
            }

            // This is a MouseMove event with a mouse button pressed. Call mouseDragged.
            if (!m_client.mouseDragged)
                return false;

            return m_client.mouseDragged(toAPI(pageBanner), toAPI(position), toAPI(button), m_client.base.clientInfo);
        }

        default:
            return false;
        }
    }
};

WKBundlePageBannerRef WKBundlePageBannerCreateBannerWithCALayer(CALayer *layer, int height, WKBundlePageBannerClientBase* wkClient)
{
    if (wkClient && wkClient->version)
        return 0;

    auto clientImpl = std::make_unique<PageBannerClientImpl>(wkClient);
    return toAPI(PageBanner::create(layer, height, clientImpl.release()).leakRef());
}

CALayer * WKBundlePageBannerGetLayer(WKBundlePageBannerRef pageBanner)
{
    return toImpl(pageBanner)->layer();
}
