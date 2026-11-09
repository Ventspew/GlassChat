package wa

import (
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/store"
	"google.golang.org/protobuf/proto"
)

// applyCompanionFingerprint makes the linked device look like a Chrome WhatsApp Web
// companion instead of the stock whatsmeow UNKNOWN / "whatsmeow" identity.
//
// Inspired by:
//   - caseyng/whatsmeow fingerprint hardening (Prekey Pogo / arXiv 2504.07323)
//   - community DeviceProps guidance (CHROME companion)
//   - whatRust’s lesson: behave like official Web when possible
//
// We stay on upstream tulir/whatsmeow (the caseyng fork lags go.mau.fi/util).
// Full Chrome TLS (uTLS) / prekey batch patches require a maintained fork.
// This is NOT ban-proof — see Docs/BAN_AND_CLIENT_RESEARCH.md.
func applyCompanionFingerprint(client *whatsmeow.Client) {
	_ = client
	store.SetOSInfo("Chrome", [3]uint32{124, 0, 0})
	store.DeviceProps.Os = proto.String("Chrome")
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_CHROME.Enum()
	store.DeviceProps.RequireFullSync = proto.Bool(true)
	if store.DeviceProps.Version == nil {
		store.DeviceProps.Version = &waCompanionReg.DeviceProps_AppVersion{}
	}
	store.DeviceProps.Version.Primary = proto.Uint32(124)
	store.DeviceProps.Version.Secondary = proto.Uint32(0)
	store.DeviceProps.Version.Tertiary = proto.Uint32(0)
}
