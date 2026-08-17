// Copyright 2013 @atotto. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build darwin
// +build darwin

package clip

import (
	"os"
	"os/exec"
)

// type DarwinClip struct{}

var (
	pasteCmdArgs = "pbpaste"
	copyCmdArgs  = "pbcopy"
)

func getPasteCommand() *exec.Cmd {
	cmd := exec.Command(pasteCmdArgs)
	// Without a UTF-8 locale, pbpaste transcodes to ASCII and turns non-ASCII chars into '?'.
	cmd.Env = append(os.Environ(), "LANG=en_US.UTF-8")
	return cmd
}

func getCopyCommand() *exec.Cmd {
	cmd := exec.Command(copyCmdArgs)
	// Without a UTF-8 locale, pbcopy misreads UTF-8 input as mojibake.
	cmd.Env = append(os.Environ(), "LANG=en_US.UTF-8")
	return cmd
}

func readAll() (string, error) {
	pasteCmd := getPasteCommand()
	out, err := pasteCmd.Output()
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// WriteAll writes to clipboard
func WriteAll(text string) error {
	copyCmd := getCopyCommand()
	in, err := copyCmd.StdinPipe()
	if err != nil {
		return err
	}

	if err := copyCmd.Start(); err != nil {
		return err
	}
	if _, err := in.Write([]byte(text)); err != nil {
		return err
	}
	if err := in.Close(); err != nil {
		return err
	}
	return copyCmd.Wait()
}
