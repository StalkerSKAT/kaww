void onInit(CBlob@ this)
{
	this.set_string("eat sound", "/Eat.ogg");
	this.getCurrentScript().runFlags |= Script::remove_after_this;
	this.server_SetTimeToDie(40);
	this.Tag("ignore_arrow");
	this.Tag("ignore_saw");
	this.Tag("trap");
}
