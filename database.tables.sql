-- MySQL dump 10.11
--
-- Host: localhost    Database: govtrack
-- ------------------------------------------------------
-- Server version	5.0.45

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `people`
--

DROP TABLE IF EXISTS `people`;
CREATE TABLE `people` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `firstname` tinytext character set utf8 NOT NULL,
  `middlename` tinytext character set utf8,
  `nickname` tinytext character set utf8,
  `lastname` tinytext character set utf8 NOT NULL,
  `namemod` tinytext character set latin1,
  `lastnameenc` tinytext collate utf8_bin NOT NULL,
  `lastnamealt` tinytext collate utf8_bin,
  `birthday` date default '0000-00-00',
  `gender` char(1) character set latin1 NOT NULL default '',
  `religion` tinytext character set latin1,
  `osid` varchar(50) character set latin1 default NULL,
  `bioguideid` varchar(7) character set utf8 default NULL,
  `pvsid` int(11) default NULL,
  `fecid` char(9) collate utf8_bin default NULL,
  `metavidid` tinytext collate utf8_bin,
  `youtubeid` varchar(36) character set utf8 default NULL,
  `twitterid` tinytext collate utf8_bin,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `bioguideid` (`bioguideid`),
  KEY `lastname` (`lastname`(30)),
  KEY `middlename` (`middlename`(15)),
  KEY `lastnameenc` (`lastnameenc`(15)),
  KEY `lastnamealt` (`lastnamealt`(15))
) ENGINE=MyISAM AUTO_INCREMENT=412333 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

--
-- Table structure for table `people_roles`
--

DROP TABLE IF EXISTS `people_roles`;
CREATE TABLE `people_roles` (
  `personroleid` int(11) NOT NULL auto_increment,
  `personid` int(11) NOT NULL default '0',
  `type` varchar(8) character set utf8 NOT NULL default '',
  `startdate` date default '0000-00-00',
  `enddate` date default '0000-00-00',
  `party` tinytext character set utf8,
  `state` varchar(5) character set utf8 default NULL,
  `district` smallint(6) default '0',
  `class` varchar(8) character set utf8 default NULL,
  `url` varchar(100) character set utf8 default NULL,
  `title` enum('REP','DEL','RC') NOT NULL default 'REP',
  PRIMARY KEY  (`personroleid`),
  KEY `personid` (`personid`),
  KEY `state` (`state`,`enddate`)
) ENGINE=MyISAM AUTO_INCREMENT=42409 DEFAULT CHARSET=latin1;

--
-- Table structure for table `people_votes`
--

DROP TABLE IF EXISTS `people_votes`;
CREATE TABLE `people_votes` (
  `personid` int(11) NOT NULL,
  `voteid` varchar(10) collate utf8_unicode_ci NOT NULL,
  `date` datetime NOT NULL,
  `vote` enum('+','-','0','P','X') collate utf8_unicode_ci NOT NULL,
  `displayas` tinytext collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`personid`,`voteid`),
  KEY `SECONDARY` (`voteid`,`personid`),
  KEY `bydate` (`personid`,`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `people_committees`
--

DROP TABLE IF EXISTS `people_committees`;
CREATE TABLE `people_committees` (
  `people_committee_id` int(11) NOT NULL auto_increment,
  `personid` int(11) NOT NULL default '0',
  `committeeid` varchar(10) collate utf8_unicode_ci NOT NULL default '',
  `type` text collate utf8_unicode_ci NOT NULL,
  `name` text collate utf8_unicode_ci NOT NULL,
  `subname` text collate utf8_unicode_ci,
  `role` text collate utf8_unicode_ci,
  `housecode` text collate utf8_unicode_ci NOT NULL,
  `senatecode` text collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`people_committee_id`),
  KEY `personid` (`personid`)
) ENGINE=MyISAM AUTO_INCREMENT=122144 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `committees`
--

DROP TABLE IF EXISTS `committees`;
CREATE TABLE `committees` (
  `id` varchar(10) collate utf8_unicode_ci NOT NULL default '',
  `type` varchar(10) collate utf8_unicode_ci NOT NULL default '',
  `parent` varchar(10) collate utf8_unicode_ci default NULL,
  `displayname` text collate utf8_unicode_ci NOT NULL,
  `thomasname` text collate utf8_unicode_ci NOT NULL,
  `url` text collate utf8_unicode_ci,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `thomasname` (`thomasname`(100),`parent`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2009-05-24 20:15:53
