package middleware

import (
	"errors"
	"io/ioutil"
	"log"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/baccenfutter/cion/config"
	"github.com/labstack/echo"
)

type (
	// CionHeaders holds the X-Cion header fields.
	CionHeaders struct {
		Zone       string `json:"zone"`
		AuthKey    string `json:"auth_key"`
		UpdateType string `json:"update_type"`
		DeleteType string `json:"delete_type"`
		Debug      bool   `json:"debug"`
	}
)

// Cion returns the cion middleware.
func Cion() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			headers := CionHeaders{}

			authKey := c.Request().Header.Get("x-cion-auth-key")
			if authKey == "" {
				return echo.NewHTTPError(
					http.StatusUnauthorized,
					"Please specify X-Cion-Auth-Key header!")
			}

			// authenticate the user
			username := c.Param("zone")
			err := authenticate(username, []byte(authKey))
			if err != nil {
				return echo.NewHTTPError(http.StatusUnauthorized, err)
			}

			// Add authkey and zone to cion headers.
			headers.AuthKey = authKey
			headers.Zone = username

			// Add x-cion-update-type header if present.
			headers.UpdateType = c.Request().Header.Get("x-cion-update-type")
			log.Println("UPDATE-TYPE:", headers.UpdateType)

			// Add x-cion-delete-type header if present.
			headers.DeleteType = c.Request().Header.Get("x-cion-delete-type")
			log.Println("DELETE-TYPE:", headers.UpdateType)

			mode := c.Request().Header.Get("x-cion-mode")
			if strings.ToLower(mode) == "debug" {
				headers.Debug = true
			}

			c.Set("cion_headers", headers)
			return next(c)
		}
	}
}

// authenticate takes a username and a key and returns an error if the user can
// not be authenticated successfully.
func authenticate(username string, authKey []byte) error {
	keyDir := config.Config().KeyDir
	filePath := filepath.Join(keyDir, string(username)+".key")
	key, err := ioutil.ReadFile(filePath)
	if err != nil {
		return err
	}
	if string(key) != string(authKey) {
		return errors.New("authentication failed")
	}
	return nil
}
