import { field, contains } from '@cardstack/base/card-api';
import UserIcon from '@cardstack/boxel-icons/user';
import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { MarketplaceMember } from './marketplace-member';

// SellerProfile — a marketplace member who sells. Only `rating` is added (it
// has no meaning on a buyer); the member formats read it to show the seller
// view, so every format is inherited.
export class SellerProfile extends MarketplaceMember {
  static displayName = 'Seller Profile';
  static icon = UserIcon;

  // Unrated sellers show an em dash, never a default score.
  @field rating = contains(ScoreField);
}

export default SellerProfile;
