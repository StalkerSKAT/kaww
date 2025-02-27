#include "VehicleCommon.as"
#include "GenericButtonCommon.as";
#include "Explosion.as"
#include "Hitters.as"
#include "PerksCommon.as";

const u16 cooldown_time = 600;
const u16 cycle_cooldown = 90;
const u8 barrel_compression = 8; // max barrel movement
const u16 recoil = 120;
const u8 cassette_size = 4;

const s16 init_gunoffset_angle = -3; // up by so many degrees

// 0 == up, 90 == sideways
f32 high_angle = 62.0f;
f32 low_angle = 115.0f;

void onInit(CBlob@ this)
{
	this.Tag("vehicle");
	this.Tag("turret");
	this.Tag("tank");
	this.Tag("autoturret");
	this.Tag("blocks bullet");

	this.set_u16("cooldown_time", cooldown_time);
	this.set_u8("cassette_size", cassette_size);

	Vehicle_Setup(this,
	    0.0f, // move speed
	    0.3f,  // turn speed
	    Vec2f(0.0f, -2.5f), // jump out velocity
	    true);  // inventory access

	VehicleInfo@ v; if (!this.get("VehicleInfo", @v)) {return;}

	Vehicle_AddAmmo(this, v,
	    cycle_cooldown, // fire delay (ticks)
	    1, // fire bullets amount
	    1, // fire cost
	    "mat_bolts", // bullet ammo config name
	    "105mm Shells", // name for ammo selection
	    "ballista_bolt", // bullet config name
	    //"sound_100mm", // fire sound
		"sound_105mm",
	    "EmptyFire", // empty fire sound
	    Vehicle_Fire_Style::custom,
	    Vec2f(-6.0f, -8.0f), // fire position offset
	    1); // charge time
	
	v.cassette_size = cassette_size;
	v.origin_cooldown = cooldown_time;

	Vehicle_SetWeaponAngle(this, low_angle, v);
	this.set_string("autograb blob", "mat_bolts");

	this.getShape().SetOffset(Vec2f(5, -12));

	CShape@ shape = this.getShape();
	ShapeConsts@ consts = shape.getConsts();
	consts.collideWhenAttached = true;	 // we have our own map collision

	// auto-load on creation
	// init arm sprites
	CSprite@ sprite = this.getSprite();
	CSpriteLayer@ arm = sprite.addSpriteLayer("arm", sprite.getConsts().filename, 32, 80);

	if (arm !is null)
	{
		f32 angle = low_angle;

		Animation@ anim = arm.addAnimation("default", 0, false);
		anim.AddFrame(14);

		CSpriteLayer@ arm = this.getSprite().getSpriteLayer("arm");
		if (arm !is null)
		{
			arm.SetRelativeZ(2.5f);
		}
	}

	CSpriteLayer@ tur = sprite.addSpriteLayer("turret", sprite.getConsts().filename, 32, 80);

	if (tur !is null)
	{
		f32 angle = low_angle;

		Animation@ anim = tur.addAnimation("default", 0, false);
		anim.AddFrame(15);

		CSpriteLayer@ tur = this.getSprite().getSpriteLayer("tur");
		if (tur !is null)
		{
			tur.SetRelativeZ(2.6f);
		}
	}

	// auto-load on creation
	if (getNet().isServer())
	{
		CBlob@ ammo = server_CreateBlob("mat_bolts");
		if (ammo !is null)
		{
			if (!this.server_PutInInventory(ammo))
				ammo.server_Die();

			ammo.server_SetQuantity(ammo.getQuantity()*2);
		}
	}

	sprite.SetZ(-100.0f);
	//CSpriteLayer@ front = sprite.addSpriteLayer("front layer", sprite.getConsts().filename, 80, 80);
	//if (front !is null)
	//{
	//	front.addAnimation("default", 0, false);
	//	int[] frames = { 0, 1, 2 };
	//	front.animation.AddFrames(frames);
	//	front.SetRelativeZ(0.8f);
	//	front.SetOffset(Vec2f(0.0f, 0.0f));
	//}

	u8 teamleft = getRules().get_u8("teamleft");
	u8 teamright = getRules().get_u8("teamright");
	this.set_f32("gunelevation", (this.getTeamNum() == teamright ? 270 : 90) - init_gunoffset_angle);

	sprite.SetEmitSound("Hydraulics.ogg");
	sprite.SetEmitSoundPaused(true);
	sprite.SetEmitSoundVolume(1.25f);
	sprite.SetEmitSoundSpeed(1.25f);
}

f32 getAngle(CBlob@ this, const u8 charge, VehicleInfo@ v)
{
	f32 angle = 180.0f; //we'll know if this goes wrong :)
	bool facing_left = this.isFacingLeft();
	AttachmentPoint@ gunner = this.getAttachments().getAttachmentPointByName("GUNNER");

	bool not_found = true;

	if (gunner !is null && gunner.getOccupied() !is null && !gunner.isKeyPressed(key_action2) && !this.hasTag("broken"))
	{
		Vec2f aim_vec = gunner.getPosition()-Vec2f(0,4) - gunner.getAimPos();

		if ((!facing_left && aim_vec.x < 0) ||
		        (facing_left && aim_vec.x > 0))
		{
			this.getSprite().SetEmitSoundPaused(false);
			this.getSprite().SetEmitSoundVolume(1.25f);

			if (aim_vec.x > 0) { aim_vec.x = -aim_vec.x; }

			aim_vec.RotateBy((facing_left ? 1 : -1) * this.getAngleDegrees());

			angle = (-(aim_vec).getAngle() + 270.0f);
			angle = Maths::Max(high_angle , Maths::Min(angle , low_angle));

			not_found = false;
		}
		else
		{
			this.getSprite().SetEmitSoundPaused(true);
		}
	}

	if (not_found)
	{
		angle = Maths::Abs(Vehicle_getWeaponAngle(this, v));
		this.Tag("nogunner");
		return (facing_left ? -angle : angle);
	}

	this.Untag("nogunner");

	if (facing_left) { angle *= -1; }

	return angle;
}

void onTick(CBlob@ this)
{
	VehicleInfo@ v;
	if (!this.get("VehicleInfo", @v))
	{
		return;
	}

	this.getShape().SetOffset(this.isFacingLeft()? Vec2f(-5.0f, -12): Vec2f(5, -12));
	
	s16 currentAngle = this.get_f32("gunelevation");

	if (getGameTime() % 5 == 0)
	{
		AttachmentPoint@ point = this.getAttachments().getAttachmentPointByName("BOW");
		if (point !is null && point.getOccupied() !is null)
		{
			CBlob@ tur = point.getOccupied();
			tur.SetFacingLeft(this.isFacingLeft());
			if (isServer()) tur.server_setTeamNum(this.getTeamNum());
		}
	}

	bool fl = this.isFacingLeft();
	if (this.hasAttached() || this.getTickSinceCreated() < 30)
	{
		bool broken = this.hasTag("broken");
		if (!broken) Vehicle_StandardControls(this, v);

		if (v.cooldown_time > 0)
		{
			v.cooldown_time--;
		}

		f32 angle = getAngle(this, v.charge, v);
		s16 targetAngle;
		bool isOperator = false;
		
		AttachmentPoint@ gunner = this.getAttachments().getAttachmentPointByName("GUNNER");
		if (gunner !is null && gunner.getOccupied() !is null && !broken)
		{
			Vec2f aim_vec = gunner.getPosition() - gunner.getAimPos();
			CBlob@ oc = gunner.getOccupied();
			if (oc.isMyPlayer())
			{
				CControls@ c = oc.getControls();
				if (c !is null)
				{
					if (c.isKeyPressed(KEY_LSHIFT) && c.isKeyPressed(KEY_KEY_R))
					{
						CBitStream params;
						params.write_bool(true);
						this.SendCommand(this.getCommandID("reload_mag"), params);
					}
				}
			}
			
			CPlayer@ p = oc.getPlayer();
			PerkStats@ stats;
			if (p !is null && p.get("PerkStats", @stats))
			{
				isOperator = stats.id == Perks::operator;
				high_angle = 70.0f - stats.top_angle;
				low_angle =  105.0f + stats.down_angle;
			}

			bool facing_left = fl;
		}

		if (angle < 0)
		{
			targetAngle = 360 + angle; // facing left
		}
		else
		{
			targetAngle = angle;
		}

		this.getSprite().SetEmitSoundPaused(true);

		if (!this.hasTag("nogunner"))
		{
			//if (getGameTime()%2==0)
			{
				int factor = 1;
				if (isOperator) factor = 2;

				int difference = Maths::Abs(currentAngle - targetAngle);

				if (difference >= 1)
				{
					int req = Maths::Min(difference, factor);

					if (difference < 180) {
						if (currentAngle < targetAngle) currentAngle += req;
						else currentAngle -= req;
					} else {
						if (currentAngle < targetAngle) currentAngle += req;
						else currentAngle += req;
					}
					this.getSprite().SetEmitSoundPaused(false);
					this.getSprite().SetEmitSoundVolume(1.25f);
					this.set_f32("gunelevation", ((currentAngle % 360.0f) + 360.0f) % 360.0f);
					Vehicle_SetWeaponAngle(this, this.get_f32("gunelevation"), v);
				}
				else if (difference <= factor)
				{
					factor = 1;
				}
			}
		}

		if (fl) this.set_f32("gunelevation", Maths::Min(360.0f-high_angle, Maths::Max(this.get_f32("gunelevation") , 360.0f-low_angle)));
		else this.set_f32("gunelevation", Maths::Max(high_angle, Maths::Min(this.get_f32("gunelevation") , low_angle)));
	}

	if (fl) this.set_f32("gunelevation", Maths::Min(360.0f-high_angle, Maths::Max(this.get_f32("gunelevation") , 360.0f-low_angle)));
	else this.set_f32("gunelevation", Maths::Max(high_angle, Maths::Min(this.get_f32("gunelevation") , low_angle)));

	// intended shitcode fix it if you really want
	CSprite@ sprite = this.getSprite();
	f32 x = fl ? 2.0f : -4.0f;
	f32 y = fl ? -37.0f : -45.0f;
	CSpriteLayer@ arm = sprite.getSpriteLayer("arm");
	if (arm !is null)
	{
		arm.ResetTransform();
		arm.RotateBy(this.get_f32("gunelevation"), Vec2f(4.0f, 22.0f));
		arm.SetOffset(Vec2f(x, y+3));
		arm.SetOffset(arm.getOffset() - Vec2f(-barrel_compression + Maths::Min(v.getCurrentAmmo().fire_delay - v.cooldown_time, barrel_compression), 0).RotateBy(fl ? 90+this.get_f32("gunelevation") : 90-this.get_f32("gunelevation")));
		arm.SetRelativeZ(-50.0f);
	}
	CSpriteLayer@ tur = sprite.getSpriteLayer("turret");
	if (tur !is null)
	{
		tur.ResetTransform();
		tur.RotateBy(this.get_f32("gunelevation"), Vec2f(0.0f, 17.0f));
		tur.SetOffset(Vec2f(x, y)+(fl?Vec2f(-4,4):Vec2f(2,12)));
		tur.SetRelativeZ(-49.0f);
	}
}

// Blow up
void onDie(CBlob@ this)
{
	//DoExplosion(this);

	//Explode(this, 64.0f, 1.0f);

	this.getSprite().PlaySound("/turret_die");
}

void onCommand(CBlob@ this, u8 cmd, CBitStream @params)
{
	if (cmd == this.getCommandID("fire blob"))
	{
		CBlob@ blob = getBlobByNetworkID(params.read_netid());
		const u8 charge = params.read_u8();
		
		VehicleInfo@ v;
		if (!this.get("VehicleInfo", @v))
		{
			return;
		}
		
		// check for valid ammo
		if (blob.getName() != v.getCurrentAmmo().bullet_name)
		{
			return;
		}
		
		Vehicle_onFire(this, v, blob, charge);
	}
}

bool Vehicle_canFire(CBlob@ this, VehicleInfo@ v, bool isActionPressed, bool wasActionPressed, u8 &out chargeValue)
{
	v.firing = isActionPressed;
	bool hasammo = v.getCurrentAmmo().loaded_ammo > 0;

	u8 charge = v.charge;
	if ((charge > 0 || isActionPressed) && hasammo)
	{
		if (charge < v.getCurrentAmmo().max_charge_time && isActionPressed)
		{
			charge++;
			v.charge = charge;

			chargeValue = charge;
			return false;
		}
		chargeValue = charge;
		return true;
	}

	return false;
}

void Vehicle_onFire(CBlob@ this, VehicleInfo@ v, CBlob@ bullet, const u8 _charge)
{
	this.getSprite().PlayRandomSound(v.getCurrentAmmo().fire_sound);
	if (bullet !is null)
	{
		bullet.Tag("shell");
		u8 charge_prop = _charge;
		bool fl = this.isFacingLeft();
		f32 angle = this.get_f32("gunelevation") + this.getAngleDegrees();
		Vec2f vel = Vec2f(0.0f, -27.5f).RotateBy(angle);
		bullet.setVelocity(vel);
		Vec2f pos = this.getPosition() + Vec2f((fl ? -1 : 1)*56.0f, -17.5f).RotateBy((fl?angle+90:angle-90));
		bullet.setPosition(pos + (fl?Vec2f(-12.0f,0):Vec2f(12.0f,0)).RotateBy((fl?angle+90:angle-90)));
		pos = pos + (fl?Vec2f(-5.0f,0):Vec2f(5.0f,0));

		CBlob@ hull = getBlobByNetworkID(this.get_u16("tankid"));

		bool not_found = true;

		if (hull !is null)
		{
			hull.AddForce(Vec2f(hull.isFacingLeft() ? (recoil*5.0f) : (recoil*-5.0f), 0.0f));
		}

		if (isClient())
		{
			bool facing = fl;
			for (int i = 0; i < 16; i++)
			{
				ParticleAnimated("LargeSmokeGray", pos, this.getShape().getVelocity() + getRandomVelocity(0.0f, XORRandom(45) * 0.005f, 360) + vel/(10+XORRandom(24)), float(XORRandom(360)), 0.5f + XORRandom(40) * 0.01f, 2 + XORRandom(2), -0.0031f, true);
				//ParticleAnimated("LargeSmoke", pos, this.getShape().getVelocity() + getRandomVelocity(0.0f, XORRandom(45) * 0.005f, 360) + vel/(40+XORRandom(24)), float(XORRandom(360)), 0.5f + XORRandom(40) * 0.01f, 6 + XORRandom(3), -0.0031f, true);
			}

			for (int i = 0; i < 4; i++)
			{
				float angle = Maths::ATan2(vel.y, vel.x) + 20;
				ParticleAnimated("LargeSmoke", pos, this.getShape().getVelocity() + Vec2f(Maths::Cos(angle), Maths::Sin(angle))/2, float(XORRandom(360)), 0.4f + XORRandom(40) * 0.01f, 4 + XORRandom(3), -0.0031f, true);
				float angle2 = Maths::ATan2(vel.y, vel.x) - 20;
				ParticleAnimated("LargeSmoke", pos, this.getShape().getVelocity() + Vec2f(Maths::Cos(angle2), Maths::Sin(angle2))/2, float(XORRandom(360)), 0.4f + XORRandom(40) * 0.01f, 4 + XORRandom(3), -0.0031f, true);

				ParticleAnimated("LargeSmokeGray", pos, this.getShape().getVelocity() + getRandomVelocity(0.0f, XORRandom(45) * 0.005f, 360) + vel/(40+XORRandom(24)), float(XORRandom(360)), 0.5f + XORRandom(40) * 0.01f, 6 + XORRandom(3), -0.0031f, true);
				ParticleAnimated("Explosion", pos, this.getShape().getVelocity() + getRandomVelocity(0.0f, XORRandom(45) * 0.005f, 360) + vel/(40+XORRandom(24)), float(XORRandom(360)), 0.5f + XORRandom(40) * 0.01f, 2, -0.0031f, true);
			}
		}

		makeGibParticle(
		"EmptyShell",               		// file name
		this.getPosition(),                 // position
		(Vec2f(0.0f,-0.5f) + getRandomVelocity(90, 2, 360)), // velocity
		0,                                  // column
		0,                                  // row
		Vec2f(16, 16),                      // frame size
		0.5f,                               // scale?
		0,                                  // ?
		"ShellCasing",                      // sound
		this.get_u8("team_color"));         // team number
	}	

	v.last_charge = _charge;
	v.charge = 0;

	if (v.fired_amount < cassette_size)
	{
		v.getCurrentAmmo().fire_delay = cycle_cooldown;
		v.cooldown_time = cycle_cooldown;
		v.fire_time = 0;
	}
	else
	{
		v.getCurrentAmmo().fire_delay = cooldown_time;
		v.cooldown_time = cooldown_time;
		v.fired_amount = 0;
	}

	this.set_u32("fired_amount", v.fired_amount);
}

bool doesCollideWithBlob(CBlob@ this, CBlob@ blob)
{
	if (blob.getTeamNum() == this.getTeamNum()) return false;
	if (blob.hasTag("vehicle") || blob.hasTag("boat"))
	{
		return true;
	}

	if (blob.hasTag("flesh") && !blob.isAttached())
	{
		return true;
	}
	else
	{
		return Vehicle_doesCollideWithBlob_ground(this, blob);
	}
}

void onAttach(CBlob@ this, CBlob@ attached, AttachmentPoint @attachedPoint)
{
	if (attached.hasTag("player")) attached.Tag("covered");
	VehicleInfo@ v;
	if (!this.get("VehicleInfo", @v))
	{
		return;
	}
	attachedPoint.offsetZ = 1.0f;
	this.getShape().SetStatic(true);
	Vehicle_onAttach(this, v, attached, attachedPoint);
}

void onDetach(CBlob@ this, CBlob@ detached, AttachmentPoint@ attachedPoint)
{
	if (detached.hasTag("player")) detached.Untag("covered");
	VehicleInfo@ v;
	if (!this.get("VehicleInfo", @v))
	{
		return;
	}
	this.getShape().SetStatic(false);
	Vehicle_onDetach(this, v, detached, attachedPoint);
}