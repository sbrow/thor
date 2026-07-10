package main

Site :: struct {
	base_url: string,
	title:    string,
	socials:  []Social_Icon,
}

Social_Icon :: struct {
	name: string,
	url:  string,
}

