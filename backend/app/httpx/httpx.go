// Package httpx holds the JSON response helpers and the error policy:
// a 4xx carries a message the client can act on, anything else is logged
// and answered with an opaque 500.
package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
)

// Error is a client-facing failure with an HTTP status and a stable code.
type Error struct {
	Status  int
	Code    string
	Message string
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

func NewError(status int, code, message string) *Error {
	return &Error{Status: status, Code: code, Message: message}
}

func BadRequest(code, msg string) *Error { return NewError(http.StatusBadRequest, code, msg) }
func NotFound(msg string) *Error         { return NewError(http.StatusNotFound, "not_found", msg) }
func Conflict(code, msg string) *Error   { return NewError(http.StatusConflict, code, msg) }

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// JSON writes v with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// NoContent writes 204.
func NoContent(w http.ResponseWriter) { w.WriteHeader(http.StatusNoContent) }

// Fail writes err: an *Error as-is, anything else as a logged opaque 500.
func Fail(w http.ResponseWriter, r *http.Request, err error) {
	var e *Error
	if !errors.As(err, &e) {
		slog.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
		e = NewError(http.StatusInternalServerError, "internal_error", "Внутренняя ошибка сервера")
	}
	var body errorBody
	body.Error.Code = e.Code
	body.Error.Message = e.Message
	JSON(w, e.Status, body)
}

// Decode reads a JSON body into v (max 1 MiB) and rejects unknown garbage.
func Decode(r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		return BadRequest("invalid_json", "Некорректный JSON: "+err.Error())
	}
	return nil
}
