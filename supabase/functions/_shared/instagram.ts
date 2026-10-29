/**
 * The one piece of Instagram knowledge both Instagram functions need.
 *
 * A store page renders posts by embedding them, so what it stores is the shortcode rather
 * than an image URL — see 20261029000001_store_instagram.sql for why. Graph hands back a
 * permalink, not a shortcode, so the two have to be reconciled somewhere, and doing it here
 * keeps the rule identical to norm_instagram_shortcode() in the database.
 */

/** The shortcode in an Instagram post or reel permalink, or null if it is neither. */
export function shortcodeFromPermalink(permalink: string | null | undefined): string | null {
  if (!permalink) return null;
  const m = /instagram\.com\/(?:[^/?#\s]+\/)?(?:p|reel|reels|tv)\/([^/?#\s]+)/i.exec(permalink);
  const code = m?.[1];
  if (!code || !/^[A-Za-z0-9_-]{5,40}$/.test(code)) return null;
  return code;
}
