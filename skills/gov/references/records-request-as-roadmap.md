# Records Request as Reusable Roadmap

**Born:** 2026-08-26, NY Correction Law § 508 jail-to-hospital psychiatric transfer campaign.
**Objective that produced it:** *"send a record request out to those people about how they handle it
so they have to expose how the process works for anyone they get approved and transfer under it —
so they basically tell us everything we need to do to get a successful transfer for anyone in a
similar situation."*

The ask was not "get me my brother's file." It was **"make the agency publish its own operating
manual for a statute it is barely using."** That reframing is the whole method, and it generalizes
to any statutory right that exists on paper but is administered invisibly.

---

## 1. The design principle: no PHI, produce-or-certify, both outcomes useful

Three deliberate choices, each of which removes a standard agency escape hatch:

1. **Seek NO personally identifying information.** Every item asks for policies, blank exemplar
   forms, acceptance criteria, guidance, and aggregate statistics. Nothing names an individual.
   → the privacy exemption (NY POL § 87(2)(b), federal FOIA (b)(6)) is **off the board entirely**,
   and no HIPAA authorization is needed. The subject's own records are a *separate request on a
   separate track* — never mix them.
2. **Blank/exemplar forms, never completed ones.** Same reason. "Produce a blank copy of the
   certification form your facility uses" is unanswerable with a privacy objection.
3. **Frame every item to force a produce-or-certify answer.** Under **NY POL § 89(3)(a)** and
   **21 NYCRR § 1401.2(b)(7)**, an agency that cannot locate a record must **certify** either that
   it is not the custodian or that the record "cannot be found after diligent search." So:
   - Records exist → you get the roadmap.
   - Records do not exist → **the certification is itself the finding**: there is no written
     standard governing who receives this statutory benefit. That is the oversight referral, the
     press story, and the legislative ask, all in one signed document.

**Both outcomes are useful. That is the point.** Design so you cannot lose.

Federal analog: 5 U.S.C. § 552(a)(3) + the agency's own FOIA regs; a "no responsive records"
determination is an appealable, citable admission.

---

## 2. The comparator-custodian pattern (use when the primary custodian is politically constrained)

**The problem:** the agency you most need to answer is often the one your lawyer is negotiating
with. Filing against them can undercut the negotiation.

**The move:** file the *same* request to **peer agencies with identical statutory duties and no
stake in your matter**, plus the **state-level agency that supervises all of them**.

Example: in one campaign the primary custodian (a county sheriff) was held while counsel
negotiated. The request instead went to:

| Tier | Custodian | Why |
|---|---|---|
| State — accepting agency | the state mental-health authority | decides who gets admitted; holds the criteria |
| State — oversight | the state corrections-oversight commission | sets the jail standards AND receives the incident reports |
| State — judiciary (admin) | the state court-administration office | the "jointly adopted rules" half |
| Peer county A | a neighboring county | same duty, no stake |
| Peer county B | a neighboring county | same duty, no stake |
| Peer county C | a neighboring county | same duty, no stake |

**Why this is often *better* than hitting the primary:** peer counties have no reason to stonewall,
so they answer faster and more completely — and their answers become the **benchmark you hold the
primary to**. "Broome produced its § 508 policy in nine days; you have certified you have none."
That comparison is worth more than the primary's own grudging production.

**Corollary — target the custodians whose process is NOT already published.** The user's own
instruction: *"especially some of them that maybe weren't publicly online."* An agency that already
posts its policy teaches you nothing. The ones with nothing on the website are the ones whose
answer is new information.

---

## 3. ⛔ CHECK THE REQUESTER'S OWN SENT MAIL BEFORE YOU FILE

**This is a hard gate, and it fired for real.** Two letters were fully built and about to go to a
county custodian when a Gmail search turned up that **the user had already filed the same ground
three days earlier — and his version was broader.**

Filing the duplicate would have: opened a second ticket on the same clock, handed the county a
consolidation excuse, and made the requester look disorganized to the custodians who were cc'd on
both.

```bash
gog gmail messages search "FOIL OR records OR request" -a <acct> --max 25
```

Worse, the already-sent letter **contained the answer to a research question I had just told the
user was unanswerable** (it cited the exact regulation I claimed "could not be located in any
published source" — a claim that had already gone out in a filed FOIL and required a correction
letter).

**RULE: the requester's own sent folder is a primary source. Search it before you file, before you
research, and before you assert any negative.** This is the Negative-Result Rule with the scope
error made concrete: a same-corpus control validates your *pattern*, never your *scope*.

---

## 4. Finding rules a statute references but the agency doesn't publish

When a statute says duties are governed by *"rules jointly adopted by X and Y"* and neither X nor Y
publishes them, **they usually exist in the codified regulation compilation, not on the agency
website.**

- NY → search **NYCRR by subject**, not by agency. The § 508 rules turned out to be
  **14 NYCRR Part 18**, titled for the *procedure*, not for either adopting body.
- Federal → the CFR part, not the agency's guidance page.
- **Cornell LII (`law.cornell.edu/regulations/new-york/<cite>`) serves NYCRR cleanly by plain
  curl** when nysenate.gov, justia, and nycourts.gov all Cloudflare-403 you. This is the single
  most useful access fact in the whole campaign.

**Then look for the two defects agencies hide behind, and pre-empt them:**
1. **Citation mismatch** — the regulation cites a statutory subdivision that has since been
   renumbered (Part 18 cites § 508(3); the live statute is § 508(2)). The reg was never conformed.
2. **Ordering conflict** — the statute lists actors in one order, the regulation's actual procedure
   runs the inverse. The regulation is the instrument the statute points to *for procedure*, so it
   governs the sequence — say so before they say the opposite.

---

## 5. Read the WHOLE statutory section — count the routes

The first analysis of § 508 told counsel the transfer was gated behind the jail physician. Reading
the full section revealed **three independent routes**, and the physician route was the *slowest*:

- one requiring only the **warden's** certification, with a mandatory "shall … forthwith" and a
  receiving hospital that "**shall admit**" — no gatekeeper at all;
- one requiring only the **sheriff's own written order**, turning on facility inadequacy;
- and the physician route, which was the one everyone had stalled on.

**Generalize: when you are told "the process requires X and X won't cooperate," read the entire
section and enumerate every route to the same outcome.** Agencies and even counsel routinely
know only the customary path. The statute frequently has two others.

**Then ask the right question.** Never "will you help?" — always **"on what basis have you concluded
[the mandatory provision] is not satisfied?"** That converts a discretionary favor into a decision
they must justify in writing.

---

## 6. Match the evidence to the forum's actual statutory standard

The strongest facts in a matter can be **actively harmful in the wrong forum.**

Escalating in-custody psychiatric decompensation was superb evidence for a competency exam and a
hospital-transfer demand. In the **bail** forum it was poison: NY CPL § 510.10(1) frames the
securing-order question entirely around *risk of flight* — **there is no dangerousness standard** —
while a neighboring subdivision lets a court commit a qualifying violent-felony defendant. Same
facts, opposite effect, one forum over.

**Before offering a fact, read the operative standard of the forum receiving it and confirm the
fact is a factor there.** If it isn't, it is not neutral — it is ammunition for the other side.

---

## 7. The near-zero-volume statistic is the story

Pull the agency's own published counts for the statutory mechanism. In this campaign: **§ 508
admissions ran 11 → 8 → 6 → 8 → 4 across 2019–2023 — four people statewide, 0.5% of the forensic
census, down ~64% while the total census *rose*.**

**A statute written in mandatory terms operating at near-zero volume is a finding in itself.**

⚠️ **State the caveat every time or you will be discredited on it.** That figure is a point-in-time
census of *forensic facilities only*, so short stabilization stays and admissions to civil hospitals
are excluded. **It is a floor, not a total.** Say so before someone else does.

---

## 8. Channel discovery — and proving a channel does *not* exist

Before asserting "this agency publishes no email," run a **positive control**: parse the page and
confirm your extractor finds the things that *are* there (phone numbers, the full country list in a
dropdown, field labels). If the parser demonstrably works and returns zero emails, the absence is
real. If you skip the control, "no email found" means "my parser failed."

Real results from this campaign:
- **NYS Commission of Correction** — zero `mailto:` and zero email strings in the rendered DOM.
  Fax/portal/mail only. **Do not invent a FOIL email.**
- **Onondaga County** — no FOIL email and no FOIL mailing address anywhere; MachForm portal for
  Sheriff/DA, GovQA for everything else.
- **The county everyone said was portal-only** in fact had a live FOIL Officer email that the user
  had already used. **Verify the channel claim itself.**

---

## 9. 🛑 CAPTCHA = HARD STOP. Stage everything else and hand off.

**An agent must never solve, bypass, or defeat a CAPTCHA.** Several government intake forms end in
one (Onondaga's MachForm: `2 + 4 = ?`; NY AG's LEMIO form; NY AG's HCF complaint wizard; Drupal
Antibot on the AG status-request form).

**The correct pattern — stage-and-hand-off:**
1. Fill every other field programmatically.
2. **Verify by reading the values back out of the DOM**, never by trusting the fill script's return
   value.
3. Leave the CAPTCHA field untouched and the submit button unclicked.
4. Hand the user a one-line instruction: *"answer the arithmetic question and click submit."*

This respects the anti-bot control completely while reducing a 20-minute form to 15 seconds of
human work. It is not a workaround — the human genuinely completes the human-verification step.

**Trap that cost two failed fills:** a value-setter must pick the prototype **per element**.
`Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set` applied to an
`<input>` **throws**, silently aborting the rest of the script. Symptom: the textarea fills and
every field after it stays empty.

```js
const proto = el.tagName === 'TEXTAREA'
  ? window.HTMLTextAreaElement.prototype
  : window.HTMLInputElement.prototype;
Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
el.dispatchEvent(new Event('input',  {bubbles:true}));
el.dispatchEvent(new Event('change', {bubbles:true}));
```

---

## 10. Audit whether the professional actually used what you sent

When a lawyer, caseworker, or contractor receives your research, **verify adoption against the
document they actually filed** — not against their reply saying thanks.

```bash
python3 - <<'PY'
import zipfile, re, html
def txt(f):
    x = zipfile.ZipFile(f).read('word/document.xml').decode('utf8','ignore')
    return html.unescape(re.sub(r'<[^>]+>', '', re.sub(r'</w:p>', '\n', x)))
body = txt('Filing.docx').lower()
for label, needle in [("the key regulation", "18.3"), ("the named official", "director of community")]:
    print(f"{label:<28} {'YES' if needle in body else 'no'}")
PY
```

**State the caveat honestly:** if the copy you hold predates the notes you sent, you are auditing a
*draft*, not the filed version. Get the stamped copy before asserting an omission survived. An
accusation built on the wrong version costs you the relationship and the credibility.

---

## 11. Statutory framing to include in every NY FOIL letter

- **POL § 89(3)(a)** — 5-business-day acknowledgment; 20-business-day determination; where granted
  but not produced, a written reason **and a date certain**; may **not** be denied as voluminous or
  burdensome; must **certify** non-possession or "cannot be found after diligent search."
- **POL § 87(2)** — any exemption requires a **particularized and specific justification**, record
  by record, with segregable portions released. ⚠️ This sentence lives in **§ 87(2)**, *not*
  § 89(3)(a) — the Committee on Open Government itself mis-cited this in writing. Never inherit
  that cite.
- **POL § 87(1)(c)(iv)** — "preparing a copy shall not include search time or administrative costs."
- **21 NYCRR § 1401.2(b)(2)–(3)** — RAO must assist in reasonably describing records and must
  **contact** the requester where a request is voluminous.
- **Request electronic production** — no copying fee where records transmit electronically.
- **Silence past the 5-day mark = constructive denial** under § 89(4)(a), opening a 30-day appeal.
  Calendar it the day you file.

---

## 12. The one-line summary

**Ask for the process, not the file.** A request for policies, blank forms, criteria, and aggregate
counts cannot be refused on privacy grounds, must be answered or certified, and produces either the
roadmap you needed or the proof that no roadmap exists. File it to peers and supervisors, not just
to the agency you are fighting. Then hold the one you are fighting to what the peers produced.
