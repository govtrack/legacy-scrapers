-- MySQL dump 10.10
--
-- Host: localhost    Database: govtrack
-- ------------------------------------------------------
-- Server version	5.0.27

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
-- Table structure for table `billevents`
--

DROP TABLE IF EXISTS `billevents`;
CREATE TABLE `billevents` (
  `session` int(11) NOT NULL default '0',
  `type` varchar(2) collate utf8_unicode_ci NOT NULL default '',
  `number` int(11) NOT NULL default '0',
  `date` datetime NOT NULL default '0000-00-00 00:00:00',
  `eventxml` text collate utf8_unicode_ci NOT NULL,
  KEY `bill` (`session`,`type`,`number`),
  KEY `index` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `billindex`
--

DROP TABLE IF EXISTS `billindex`;
CREATE TABLE `billindex` (
  `session` int(11) NOT NULL default '0',
  `type` varchar(2) collate utf8_unicode_ci NOT NULL default '',
  `number` int(11) NOT NULL default '0',
  `idx` varchar(15) collate utf8_unicode_ci NOT NULL default '',
  `value` text collate utf8_unicode_ci NOT NULL,
  KEY `session` (`session`,`type`,`number`,`idx`),
  KEY `index` (`idx`,`value`(127),`session`),
  KEY `session_2` (`session`,`idx`,`value`(32))
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `billlinks`
--

DROP TABLE IF EXISTS `billlinks`;
CREATE TABLE `billlinks` (
  `session` int(11) NOT NULL default '0',
  `type` varchar(2) collate utf8_unicode_ci NOT NULL default '',
  `number` int(11) NOT NULL default '0',
  `source` varchar(20) collate utf8_unicode_ci NOT NULL default '',
  `url` text collate utf8_unicode_ci,
  `excerpt` text collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`session`,`type`,`number`,`source`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `billstatus`
--

DROP TABLE IF EXISTS `billstatus`;
CREATE TABLE `billstatus` (
  `session` int(11) NOT NULL default '0',
  `type` varchar(2) collate utf8_unicode_ci NOT NULL default '',
  `number` int(11) NOT NULL default '0',
  `title` text collate utf8_unicode_ci NOT NULL,
  `fulltitle` text collate utf8_unicode_ci NOT NULL,
  `statusdate` datetime NOT NULL default '0000-00-00 00:00:00',
  `statusxml` text collate utf8_unicode_ci NOT NULL,
  PRIMARY KEY  (`session`,`type`,`number`),
  KEY `fulltitle` (`fulltitle`(100)),
  KEY `statusdate` (`statusdate`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `billtitles`
--

DROP TABLE IF EXISTS `billtitles`;
CREATE TABLE `billtitles` (
  `session` int(11) NOT NULL default '0',
  `type` varchar(2) collate utf8_unicode_ci NOT NULL default '',
  `number` int(11) NOT NULL default '0',
  `title` text collate utf8_unicode_ci NOT NULL,
  `titletype` enum('official','short','popular') collate utf8_unicode_ci NOT NULL,
  KEY `title` (`title`(60)),
  KEY `bill` (`session`,`type`,`number`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Table structure for table `votes`
--

DROP TABLE IF EXISTS `votes`;
CREATE TABLE `votes` (
  `id` varchar(9) collate utf8_unicode_ci NOT NULL,
  `date` datetime NOT NULL,
  `description` text collate utf8_unicode_ci NOT NULL,
  `result` text collate utf8_unicode_ci NOT NULL,
  `billsession` int(11) default NULL,
  `billtype` varchar(2) collate utf8_unicode_ci default NULL,
  `billnumber` int(11) default NULL,
  `amdtype` char(1) collate utf8_unicode_ci default NULL,
  `amdnumber` int(11) default NULL,
  PRIMARY KEY  (`id`),
  KEY `bill` (`billsession`,`billtype`,`billnumber`),
  KEY `date` (`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2007-05-10 13:14:32
