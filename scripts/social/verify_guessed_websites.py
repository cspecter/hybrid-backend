# Check whether a guessed <brand>.com really is that brand's own cannabis site.
#
# The crawler trusts social_discovery.website absolutely -- it was built for
# websites a human entered on a profile, so it has no "is this really this
# brand?" step. These URLs are guesses, so that step has to happen here, or a
# stranger's Instagram handle ends up on a brand's page.
#
# Full TLS verification, deliberately. A bad certificate is a reason to distrust
# a guessed host, not something to switch off -- it is one of the few independent
# signals that the host is who it claims to be.
import json, re, time, urllib.request, urllib.error, ssl

UA   = "HybridBrandCheck/1.0 (+one request per domain; site verification)"
ctx  = ssl.create_default_context()
CANNA= re.compile(r"cannabis|marijuana|thc\b|cbd\b|dispensar|pre-?roll|gumm|vape|strain", re.I)
IG   = re.compile(r"instagram\.com/([A-Za-z0-9_.]{2,30})", re.I)

def tokens(b):
    return [t for t in re.split(r"[^a-z0-9]+", b.lower()) if len(t) > 2]

out = []
cands = json.load(open("candidates.json"))
for i, (brand, pid, dom) in enumerate(cands):
    rec = {"brand": brand, "profile_id": pid, "domain": dom, "status": None,
           "name_on_page": False, "cannabis": False, "instagram": None,
           "verdict": "", "note": ""}
    try:
        req = urllib.request.Request("https://" + dom,
                                     headers={"User-Agent": UA, "Accept": "text/html,*/*"})
        with urllib.request.urlopen(req, timeout=12, context=ctx) as r:
            rec["status"] = r.status
            final = r.geturl()
            body = r.read(300000).decode("utf-8", "replace")
        toks = tokens(brand)
        rec["name_on_page"] = all(t in body.lower() for t in toks) if toks else False
        rec["cannabis"] = bool(CANNA.search(body))
        m = IG.search(body)
        if m:
            rec["instagram"] = m.group(1)
        host = re.sub(r"^https?://", "", final).split("/")[0].lower().replace("www.", "")
        if host != dom:
            rec["note"] = "redirects to " + host
        if rec["name_on_page"] and rec["cannabis"]:
            rec["verdict"] = "ACCEPT"
        elif rec["cannabis"]:
            rec["verdict"] = "review: cannabis site, brand name absent"
        elif rec["name_on_page"]:
            rec["verdict"] = "review: brand name, no cannabis signal"
        else:
            rec["verdict"] = "REJECT: unrelated site"
    except urllib.error.HTTPError as e:
        rec["status"] = e.code
        rec["verdict"] = "REJECT: HTTP %s" % e.code
    except Exception as e:
        rec["verdict"] = "REJECT: " + type(e).__name__
    out.append(rec)
    print("%3d/%d %-26s %-28s %s" % (i + 1, len(cands), brand[:26], dom[:28], rec["verdict"]), flush=True)
    time.sleep(1.1)

json.dump(out, open("domain_checks.json", "w"), indent=1)
print("\ndone")
