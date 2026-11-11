# frozen_string_literal: true

# @lat: [[passkey-aaguid-registry#What an AAGUID is]]
module PasskeyAaguidRegistry
  KNOWN = {
    "dd4ec289-e01d-41c9-bb89-70fa845d4bf2" => "iCloud Keychain (Managed)",
    "fbfc3007-154e-4ecc-8c0b-6e020557d7bd" => "iCloud Keychain",
    "0ea242b4-43c4-4a1b-8b17-dd6d0b6baec6" => "Apple Passkeys",
    "ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4" => "Google Password Manager",
    "08987058-cadc-4b81-b6e1-d0a5c0dba0b1" => "Windows Hello",
    "9ddd1817-af5a-4672-a2b9-3e3dd95000a9" => "Windows Hello",
    "6028b017-b1d4-4c02-b4b3-afcdafc96bb2" => "Windows Hello",
    "adce0002-35bc-c60a-648b-0b25f1f05503" => "Chrome on Mac",
    "bada5566-a7aa-401f-bd96-45619a55120d" => "1Password",
    "531126d6-e717-415c-9320-3d9aa6981239" => "Dashlane",
    "d548826e-79b4-db40-a3d8-11116f7e8349" => "Bitwarden",
    "be727034-574a-f799-5c76-0929e0430973" => "NordPass",
    "f8a011f3-8c0a-4d15-8006-17111f9edc7d" => "YubiKey Security Key",
    "b92c3f9a-c014-4056-887f-140a2501163b" => "YubiKey Security Key",
    "6d44ba9b-f6ec-2e49-b930-0c8fe920cb73" => "YubiKey 5 Series",
    "149a2021-8ef6-4133-96b8-81f8d5b7f1f5" => "YubiKey 5 Series with Lightning",
    "fa2b99dc-9e39-4257-8f92-4a30d23c4118" => "YubiKey 5 NFC",
    "cb69481e-8ff7-4039-93ec-0a2729a154a8" => "YubiKey 5 NFC"
  }.freeze

  # @lat: [[passkey-aaguid-registry#Why the all-zeros AAGUID returns nil]]
  def self.friendly_name(aaguid)
    return nil if aaguid.nil?
    return nil if aaguid.to_s.strip.empty?
    return nil if aaguid == "00000000-0000-0000-0000-000000000000"
    KNOWN[aaguid.to_s.downcase]
  end
end
