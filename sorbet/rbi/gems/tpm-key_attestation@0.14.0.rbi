# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `tpm-key_attestation` gem.
# Please instead update this file by running `bin/tapioca gem tpm-key_attestation`.


# source://tpm-key_attestation//lib/tpm/key_attestation/version.rb#3
module TPM; end

# Section 3.2 in https://www.trustedcomputinggroup.org/wp-content/uploads/Credential_Profile_EK_V2.0_R14_published.pdf
#
# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#9
class TPM::AIKCertificate < ::SimpleDelegator
  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#23
  def conformant?; end

  private

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#56
  def empty_subject?; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#70
  def extension(oid); end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#34
  def in_use?; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#108
  def san_extension; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#92
  def san_name; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#74
  def tpm_manufacturer; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#80
  def tpm_model; end

  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#86
  def tpm_version; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#44
  def valid_basic_constraints?; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#50
  def valid_extended_key_usage?; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#60
  def valid_subject_alternative_name?; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#40
  def valid_version?; end

  class << self
    # source://tpm-key_attestation//lib/tpm/aik_certificate.rb#19
    def from_der(certificate_der); end
  end
end

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#10
TPM::AIKCertificate::ASN_V3 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#11
TPM::AIKCertificate::EMPTY_NAME = T.let(T.unsafe(nil), OpenSSL::X509::Name)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#13
TPM::AIKCertificate::OID_TCG = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#14
TPM::AIKCertificate::OID_TCG_AT_TPM_MANUFACTURER = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#15
TPM::AIKCertificate::OID_TCG_AT_TPM_MODEL = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#16
TPM::AIKCertificate::OID_TCG_AT_TPM_VERSION = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#17
TPM::AIKCertificate::OID_TCG_KP_AIK_CERTIFICATE = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/aik_certificate.rb#12
TPM::AIKCertificate::SAN_DIRECTORY_NAME = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#20
TPM::ALG_ECC = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#19
TPM::ALG_ECDSA = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#16
TPM::ALG_NULL = T.let(T.unsafe(nil), Integer)

# Algorithms
#
# source://tpm-key_attestation//lib/tpm/constants.rb#11
TPM::ALG_RSA = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#18
TPM::ALG_RSAPSS = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#17
TPM::ALG_RSASSA = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#12
TPM::ALG_SHA1 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#13
TPM::ALG_SHA256 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#14
TPM::ALG_SHA384 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#15
TPM::ALG_SHA512 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/certify_validator.rb#8
class TPM::CertifyValidator
  # @return [CertifyValidator] a new instance of CertifyValidator
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#24
  def initialize(info, signature, nonce, public_area, signature_algorithm: T.unsafe(nil), hash_algorithm: T.unsafe(nil)); end

  # Returns the value of attribute hash_algorithm.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def hash_algorithm; end

  # Returns the value of attribute info.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def info; end

  # Returns the value of attribute nonce.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def nonce; end

  # Returns the value of attribute public_area.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def public_area; end

  # Returns the value of attribute signature.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def signature; end

  # Returns the value of attribute signature_algorithm.
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#9
  def signature_algorithm; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#33
  def valid?(signing_key); end

  private

  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#60
  def attest; end

  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#64
  def openssl_hash_function; end

  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#68
  def openssl_signature_algorithm_class; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#39
  def valid_info?; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/certify_validator.rb#46
  def valid_signature?(verify_key); end
end

# source://tpm-key_attestation//lib/tpm/certify_validator.rb#17
TPM::CertifyValidator::TPM_HASH_ALG_TO_OPENSSL = T.let(T.unsafe(nil), Hash)

# source://tpm-key_attestation//lib/tpm/certify_validator.rb#11
TPM::CertifyValidator::TPM_SIGNATURE_ALG_TO_OPENSSL = T.let(T.unsafe(nil), Hash)

# ECC curves
#
# source://tpm-key_attestation//lib/tpm/constants.rb#23
TPM::ECC_NIST_P256 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#24
TPM::ECC_NIST_P384 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/constants.rb#25
TPM::ECC_NIST_P521 = T.let(T.unsafe(nil), Integer)

# Section 6 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/constants.rb#6
TPM::GENERATED_VALUE = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/key_attestation/version.rb#4
class TPM::KeyAttestation
  # @return [KeyAttestation] a new instance of KeyAttestation
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#36
  def initialize(certify_info, signature, certified_key, certificates, qualifying_data, signature_algorithm: T.unsafe(nil), hash_algorithm: T.unsafe(nil), trusted_certificates: T.unsafe(nil)); end

  # Returns the value of attribute certificates.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def certificates; end

  # Returns the value of attribute certified_key.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def certified_key; end

  # Returns the value of attribute certify_info.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def certify_info; end

  # Returns the value of attribute hash_algorithm.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def hash_algorithm; end

  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#57
  def key; end

  # Returns the value of attribute qualifying_data.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def qualifying_data; end

  # Returns the value of attribute signature.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def signature; end

  # Returns the value of attribute signature_algorithm.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def signature_algorithm; end

  # Returns the value of attribute trusted_certificates.
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#25
  def trusted_certificates; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#63
  def valid?; end

  private

  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#96
  def aik_certificate; end

  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#71
  def certify_validator; end

  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#100
  def public_area; end

  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#89
  def trust_store; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/key_attestation.rb#83
  def trustworthy?; end
end

# source://tpm-key_attestation//lib/tpm/key_attestation.rb#23
class TPM::KeyAttestation::Error < ::StandardError; end

# https://docs.microsoft.com/en-us/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-install-trusted-tpm-root-certificates
#
# source://tpm-key_attestation//lib/tpm/key_attestation.rb#14
TPM::KeyAttestation::TRUSTED_CERTIFICATES = T.let(T.unsafe(nil), Array)

# source://tpm-key_attestation//lib/tpm/key_attestation/version.rb#5
TPM::KeyAttestation::VERSION = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/public_area.rb#12
class TPM::PublicArea
  # @return [PublicArea] a new instance of PublicArea
  #
  # source://tpm-key_attestation//lib/tpm/public_area.rb#15
  def initialize(object); end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/public_area.rb#27
  def ecc?; end

  # source://tpm-key_attestation//lib/tpm/public_area.rb#23
  def key; end

  # source://tpm-key_attestation//lib/tpm/public_area.rb#19
  def name; end

  # Returns the value of attribute object.
  #
  # source://tpm-key_attestation//lib/tpm/public_area.rb#13
  def object; end

  # source://tpm-key_attestation//lib/tpm/public_area.rb#31
  def openssl_curve_name; end

  private

  # source://tpm-key_attestation//lib/tpm/public_area.rb#41
  def name_alg; end

  # source://tpm-key_attestation//lib/tpm/public_area.rb#37
  def name_digest; end

  # source://tpm-key_attestation//lib/tpm/public_area.rb#45
  def t_public; end
end

# Section 10.12.8 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/s_attest/s_certify_info.rb#8
class TPM::SAttest < ::BinData::Record
  class << self
    # source://bindata/2.5.0/lib/bindata/base.rb#19
    def deserialize(io, *args, &block); end
  end
end

# Section 10.12.3 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/s_attest/s_certify_info.rb#10
class TPM::SAttest::SCertifyInfo < ::BinData::Record; end

# source://tpm-key_attestation//lib/tpm/constants.rb#8
TPM::ST_ATTEST_CERTIFY = T.let(T.unsafe(nil), Integer)

# Section 10.4 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/sized_buffer.rb#7
class TPM::SizedBuffer < ::BinData::Record; end

# source://tpm-key_attestation//lib/tpm/public_area.rb#7
TPM::TPM_TO_OPENSSL_HASH_ALG = T.let(T.unsafe(nil), Hash)

# Section 12.2.4 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/t_public/s_ecc_parms.rb#6
class TPM::TPublic < ::BinData::Record
  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/t_public.rb#54
  def ecc?; end

  # source://tpm-key_attestation//lib/tpm/t_public.rb#58
  def key; end

  # source://tpm-key_attestation//lib/tpm/t_public.rb#70
  def openssl_curve_name; end

  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/t_public.rb#50
  def rsa?; end

  private

  # source://tpm-key_attestation//lib/tpm/t_public.rb#125
  def bn(data); end

  # source://tpm-key_attestation//lib/tpm/t_public.rb#78
  def ecc_key; end

  # source://tpm-key_attestation//lib/tpm/t_public.rb#106
  def rsa_key; end

  class << self
    # source://bindata/2.5.0/lib/bindata/base.rb#19
    def deserialize(io, *args, &block); end
  end
end

# source://tpm-key_attestation//lib/tpm/t_public.rb#22
TPM::TPublic::BN_BASE = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/t_public.rb#14
TPM::TPublic::BYTE_LENGTH = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/t_public.rb#16
TPM::TPublic::CURVE_TPM_TO_OPENSSL = T.let(T.unsafe(nil), Hash)

# source://tpm-key_attestation//lib/tpm/t_public.rb#24
TPM::TPublic::ECC_UNCOMPRESSED_POINT_INDICATOR = T.let(T.unsafe(nil), String)

# source://tpm-key_attestation//lib/tpm/t_public.rb#23
TPM::TPublic::RSA_KEY_DEFAULT_PUBLIC_EXPONENT = T.let(T.unsafe(nil), Integer)

# Section 12.2.3.6 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/t_public/s_ecc_parms.rb#8
class TPM::TPublic::SEccParms < ::BinData::Record; end

# Section 12.2.3.5 in https://trustedcomputinggroup.org/wp-content/uploads/TPM-Rev-2.0-Part-2-Structures-01.38.pdf
#
# source://tpm-key_attestation//lib/tpm/t_public/s_rsa_parms.rb#8
class TPM::TPublic::SRsaParms < ::BinData::Record; end

# source://tpm-key_attestation//lib/tpm/tpm2b_name.rb#7
class TPM::Tpm2bName < ::BinData::Record
  # @return [Boolean]
  #
  # source://tpm-key_attestation//lib/tpm/tpm2b_name.rb#13
  def valid_for?(other_name); end
end

# source://tpm-key_attestation//lib/tpm/tpms_ecc_point.rb#6
class TPM::TpmsEccPoint < ::BinData::Record; end

# source://tpm-key_attestation//lib/tpm/tpmt_ha.rb#6
class TPM::TpmtHa < ::BinData::Record; end

# source://tpm-key_attestation//lib/tpm/tpmt_ha.rb#7
TPM::TpmtHa::BYTE_LENGTH = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/tpmt_ha.rb#8
TPM::TpmtHa::DIGEST_LENGTH_SHA1 = T.let(T.unsafe(nil), Integer)

# source://tpm-key_attestation//lib/tpm/tpmt_ha.rb#9
TPM::TpmtHa::DIGEST_LENGTH_SHA256 = T.let(T.unsafe(nil), Integer)

# https://trustedcomputinggroup.org/resource/vendor-id-registry/ section 2 "TPM Capabilities Vendor ID (CAP_VID)"
#
# source://tpm-key_attestation//lib/tpm/constants.rb#28
TPM::VENDOR_IDS = T.let(T.unsafe(nil), Hash)
