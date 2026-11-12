import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';

export class PermissionManager {
  static checkPermission(permission: string): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const tokenID = bundleInfo.appInfo.accessTokenId;
      const perm: Permissions = permission as Permissions;
      const status = atManager.checkAccessTokenSync(tokenID, perm);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_e) {
      return false;
    }
  }

  static async requestPermission(permission: string): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext();
      const perm: Permissions = permission as Permissions;
      const result = await atManager.requestPermissionsFromUser(context, [perm]);
      return result.authResults.length > 0 && result.authResults.every((r: number) => r === 0);
    } catch (_e) {
      return false;
    }
  }
}
