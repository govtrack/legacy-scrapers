These are the Perl screen-scrapers that build the GovTrack.us
legislative database. The files are licensed under the terms
of the GNU AGPL, and I am very serious about the terms of the
license. You may not modify these files without sharing your
modifications.

-------------------------------------------------------------

Getting The Source Code
-----------------------

The scripts will only work on a Linux-like computer.

Check out the source code into a directory called "gather":
  svn co svn://occams.info/govtrack/gather/us gather


Setting Up Perl
---------------

To use these scripts, you'll need a ton of Perl modules
installed. You can look at the use directives to see which.
A quick way to install them all would be to run as root:

   cpan `grep "^use" * |sed -e "s/.*:use \(\S*\)[; ].*/\\1/"|sort|uniq`
   
You'll need the (non-Perl) GD image library development files
installed first.

Some other modules may still need to be installed (DateTime::Locale, DBD::mysql, perhaps others).  Running the script (see below) will tell you if it is missing any dependancies, which can then be installed with cpan.

If you are using Cygwin, see here http://search.cpan.org/dist/DBD-mysql/lib/DBD/mysql/INSTALL.pod#Windows/CygWin  
http://mail.python.org/pipermail/python-dev/2003-July/036932.html

Setting Up A Database
---------------------

You'll also need to set up access to a database. You can either
run a MySQL database locally or access the GovTrack database
remotely. In the latter case, you won't be able to do any
write operations to the database, which means some things won't
work, and it will also be considerably slower.

To set up a local MySQL database:
   create a database named "govtrack"
   set its default encoding to utf-8
   give the "govtrack@localhost" user access to it, with no password,
     or modify db.pl with the log in information
   load in the MySQL dumps into the database:
      mysql govtrack < database.tables.sql
      mysql govtrack < database.tables2.sql
      mysql govtrack < database.people.sql

To access the GovTrack database remotely:
   Set the environment variable REMOTE_DB to 1 when running any script.
   (i.e. prefix any command on the command line with "REMOTE_DB=1 ".)


Before Running The Scripts
--------------------------

The scripts are all run from within the "gather" directory, but they 
expect that a "../data/us" directory exists. So you should create a 
"data" directory along side the "gather" directory.

If you're also running a local instance of the GovTrack website (the
"front-end"), you can put the gather directory inside the "www"
directory so you reuse the website's data directory. Or symlink
www/data to a "data" directory next to "gather".

They also expect a "../mirror" directory (i.e. a mirror directory
along side the gather directory) which some scripts will use to
store files downloaded. (It stores it in files whose names are MD5
hashes of the URLs where the file came from.) The scripts won't use
the mirrored (i.e. cached) files unless CACHED=1 is set in the
environment.

Running the Scripts
-------------------

Most of the scripts are set up so you can call them from the
command line, and also so they can be require'd by another script.
When running from the command line, the first argument is generally
the name of an action to take. The rest of the arguments depend
on the command.

Here are some examples:

REMOTE_DB=1 perl parse_status.pl PARSE_STATUS 110 s 1

This fetches the status of bill S. 1 in the 110th Congress
and some related information.  The bill types are: h, s, hc, sc,
hj, sj, hr, and sr.

It writes out:

  ../data/us/110/bills/s1.xml
  The bill status file.
  
  ../data/us/110/bills.summary/s1.summary.xml
  The CRS summary (structured parse).
  
  ../data/us/110/rolls/s2007-19.xml  (etc.)
  Votes related to the bill.
  
  ../data/us/110/bills.amdt/s3.xml (etc.)
  Amendments to this bill. This happens to be the Senate's
  3rd 'amendment' in 2007. The fact that it amends S. 1 is
  encoded within the file.
  
  ../mirror/(various)
  Caches of remote pages that have been fetched, which can
  be used in place of future remote fetches by setting
  CACHED=1 in the environment (using bash, just put that
  at the very beginning like with REMOTE_DB=1).
  
The formats of the XML files are somewhat documented here:
http://wiki.govtrack.us/index.php/Data_Directory

