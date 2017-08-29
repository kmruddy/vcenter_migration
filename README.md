# VMworld US 2017 Hackathon 

## Team 6: Migrate2vcsa

### Team Members: 
- Kyle Ruddy
- Chris Nakagaki
- Heath Johnson
- Aaron Kopel
- Ken Horn
- Scott Driver
- Scott Haas

**The problem we’re trying to solve:**
VMware has created a very cool tool which allows for migrations from the Windows vCenter server to the vCenter Server Appliance. However, the tool acts in a ‘migrate and upgrade’ capacity. So there is no ability to go from a Windows vCenter of 6.0U2 to a VCSA of 6.0U2 (or even to a VCSA of 6.0U3). The same can be said of vSphere 6.5. This leaves a large hole in coverage for those users who have either upgraded to 6.5 already or are simply ready for the appliance but are not ready for an upgrade.

**Short term (aka Hackathon session) goal:** Take a couple of the standard areas where data is transferred between vCenters, and break them out into scripts/functions/modules where they can be done on a one off basis. 
Example: Take the folder structure from one vCenter and create it in the new vCenter.

**Long term goal:** Create a tool which takes each of those individual areas and combines them to allow for horizontal migrations between vCenter servers. If it’s done right, we could even offer it in a way where each of the areas could be offered as one offs. 
Example: Download and run the tool, the user is given the choice of doing a full migration or only doing individual areas. Say, if you only want to migrate permissions then this tool could also offer that.
