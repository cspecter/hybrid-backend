-- The knowledge document the reply agent answers from.
--
-- Written by reading the app, not from memory of what it is supposed to do: the
-- tab names come from the tab bar (app/hybrid-mvp.jsx), the feature descriptions
-- from the in-app walkthrough copy (app/onboarding.jsx) and the flows from the
-- screens that implement them. Anything not in here is an escalation, so it is
-- better for a section to be missing than wrong.
--
-- Seeded with ON CONFLICT DO NOTHING so editing a section in the table editor is
-- not undone by re-running migrations. To reset one section, delete the row and
-- re-run; to add a section, insert a row with a new slug.

insert into public.outreach_knowledge (slug, title, body, sort_order) values

('tabs', 'The five tabs', $md$
Hybrid has five tabs along the bottom:

- **Home** — your feed. Posts from the brands, creators and shops you follow. Double-tap a photo to like it.
- **Explore** — search products, brands and dispensaries, and find the drops and giveaways running right now. The map ("Near Me") lists dispensaries and lounges around you.
- **Stash** — everything you have saved, and your stashlists.
- **Alerts** — likes, follows, giveaway results, and deals from shops near you.
- **Profile** — your posts, your stash and your lists. Settings live here, including the option to replay the tutorial ("Show tutorial again").
$md$, 10),

('stashing', 'Stashing a product', $md$
Tap the bookmark icon on any product to stash it. Stashed products appear in the Stash tab.

Stashing is the app's main save action — there is no separate "favourite" or "wishlist".

You can stash from a product page, from a post that tags the product, from someone's profile, or from a stashlist. Where you stashed it from is recorded, which is what drives restashes (see "Restashes and attribution").
$md$, 20),

('stashlists', 'Stashlists', $md$
A stashlist is a group of products you put together — by occasion, by effect, however you like.

- Create and edit them from the Stash tab.
- Other people can **subscribe** to your stashlist, and a subscribed list shows up in their Stash tab.
- A dispensary can **feature** stashlists on its location page.
- A stashlist can be private, in which case only you see it.
$md$, 30),

('following', 'Following', $md$
Open any brand, creator or shop and tap Follow. Their posts and new drops start showing up in your Home feed.

Following a dispensary follows the brand profile that runs it, so you see that shop's menu drops and deals.

Your followers and the accounts you follow are both listed on your profile.
$md$, 40),

('giveaways', 'Giveaways', $md$
Brands run giveaways you can enter with one tap from the giveaway's page in Explore.

- One entry per person per giveaway.
- When the giveaway closes, the brand draws the winner and everyone who entered can see the result.
- If you win, you get an alert in the Alerts tab.

The agent must never say when a specific giveaway will be drawn, how many entries it has, what the odds are, or what a prize is worth, unless the live data in the email says so. If someone asks whether they won, escalate.
$md$, 50),

('deals', 'Deals', $md$
Deals are promotions run by a dispensary, listed in the Deals section and on the shop's page.

There are two kinds:

- **Code deals** — you claim the deal in the app and get a confirmation to show at the register.
- **In-store deals** — you ask the budtender for the redemption code at the counter and enter it in the app to redeem.

Each store also has a master redemption code that its staff can use for any of that store's deals, which covers a budtender who does not have an app account yet.

Some deals have a limited number of claims and show as fully claimed once they run out. Never promise a deal is still available — the app is the source of truth.
$md$, 60),

('budtender', 'Working at a shop (budtender requests)', $md$
If you work at a dispensary, open that shop's page, use the overflow menu and tap **"I work here"**.

That sends a request to the store's manager. Until a manager approves it nothing changes on your profile; the menu shows "Request pending".

Once approved, a Budtender badge appears on your profile and the shop is named under your handle, and you show up in that shop's Budtenders module.

Only a manager of that location can approve the request. The agent cannot approve one, chase one, or say how long it will take — escalate those.
$md$, 70),

('profile', 'Editing your profile', $md$
Profile tab, then Edit Profile. You can change your display name, handle, avatar, bio, website and social links.

A brand profile also carries its products; a dispensary's location page carries its address, hours, features and staff. Those are edited from the admin area by an account with access to that brand or location, not from the personal profile screen.

Brands are administered by people, not by a login on the brand itself: one or more personal accounts are given admin access to the brand profile, and they manage it from their own account.
$md$, 80),

('restashes', 'Restashes and attribution', $md$
When someone stashes a product **because of you** — from one of your posts, from one of your stashlists, or from your profile — that is recorded as a restash and counts towards your restash total.

It is the app's measure of influence: not how many people follow you, but how much of what you put up other people actually saved.

Your restash total appears on your profile and in your own numbers. A restash is attributed to where the stash came from, so the same product stashed from two different posts credits two different people.
$md$, 90),

('account', 'Accounts and signing in', $md$
You sign in with your phone number and a six-digit code — there is no password. Signing up also asks your date of birth (21+ only), an email address and a display name and handle.

First time in, the app runs a short tutorial and asks a few questions to set up your feed. You can replay it any time from Profile → Settings → "Show tutorial again".
$md$, 100),

('escalate', 'What the agent must never answer', $md$
Hand these to a human without attempting an answer:

- Bug reports, crashes, anything not working
- Complaints, or any message that reads as angry or upset
- Account problems: locked out, wrong number, deletion, verification, suspension
- Anything about money: billing, payouts, sponsorship, rates, invoices
- Legal, press, partnership or business development
- Giveaway outcomes ("did I win?"), prize value, shipping of prizes
- Anything asking for a commitment, a date, or an exception
- Anything the knowledge document does not cover

Escalating is always the correct answer when unsure. A wrong answer costs more than a slow one.
$md$, 110)

on conflict (slug) do nothing;
