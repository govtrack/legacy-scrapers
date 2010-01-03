-- MySQL dump 10.13  Distrib 5.1.37, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: govtrack
-- ------------------------------------------------------
-- Server version	5.1.37-1ubuntu5

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
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `firstname` tinytext CHARACTER SET utf8 NOT NULL,
  `middlename` tinytext CHARACTER SET utf8,
  `nickname` tinytext CHARACTER SET utf8,
  `lastname` tinytext CHARACTER SET utf8 NOT NULL,
  `namemod` tinytext CHARACTER SET latin1,
  `lastnameenc` tinytext COLLATE utf8_bin NOT NULL,
  `lastnamealt` tinytext COLLATE utf8_bin,
  `birthday` date DEFAULT '0000-00-00',
  `gender` char(1) CHARACTER SET latin1 NOT NULL DEFAULT '',
  `religion` tinytext CHARACTER SET latin1,
  `osid` varchar(50) CHARACTER SET latin1 DEFAULT NULL,
  `bioguideid` varchar(7) CHARACTER SET utf8 DEFAULT NULL,
  `pvsid` int(11) DEFAULT NULL,
  `fecid` char(9) COLLATE utf8_bin DEFAULT NULL,
  `metavidid` tinytext COLLATE utf8_bin,
  `youtubeid` varchar(36) CHARACTER SET utf8 DEFAULT NULL,
  `twitterid` tinytext COLLATE utf8_bin,
  PRIMARY KEY (`id`),
  UNIQUE KEY `bioguideid` (`bioguideid`),
  KEY `lastname` (`lastname`(30)),
  KEY `middlename` (`middlename`(15)),
  KEY `lastnameenc` (`lastnameenc`(15)),
  KEY `lastnamealt` (`lastnamealt`(15))
) ENGINE=MyISAM AUTO_INCREMENT=412384 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `people_roles`
--

DROP TABLE IF EXISTS `people_roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people_roles` (
  `personroleid` int(11) NOT NULL AUTO_INCREMENT,
  `personid` int(11) NOT NULL DEFAULT '0',
  `type` varchar(8) CHARACTER SET utf8 NOT NULL DEFAULT '',
  `startdate` date DEFAULT '0000-00-00',
  `enddate` date DEFAULT '0000-00-00',
  `party` tinytext CHARACTER SET utf8,
  `state` varchar(5) CHARACTER SET utf8 DEFAULT NULL,
  `district` smallint(6) DEFAULT '0',
  `class` tinyint(4) DEFAULT NULL,
  `url` varchar(100) CHARACTER SET utf8 DEFAULT NULL,
  `title` enum('REP','DEL','RC') NOT NULL DEFAULT 'REP',
  PRIMARY KEY (`personroleid`),
  KEY `personid` (`personid`),
  KEY `state` (`state`,`enddate`)
) ENGINE=MyISAM AUTO_INCREMENT=42503 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `people_videos`
--

DROP TABLE IF EXISTS `people_videos`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people_videos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `personid` int(11) NOT NULL,
  `source` enum('YouTube','MetaVid') NOT NULL,
  `date` datetime NOT NULL,
  `title` tinytext NOT NULL,
  `link` tinytext CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `sourcedata` text CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `thumbnail` tinytext NOT NULL,
  PRIMARY KEY (`id`),
  KEY `personid` (`personid`,`date`),
  KEY `date` (`date`),
  KEY `link` (`link`(127))
) ENGINE=MyISAM AUTO_INCREMENT=3975156 DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `people_votes`
--

DROP TABLE IF EXISTS `people_votes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people_votes` (
  `personid` int(11) NOT NULL,
  `voteid` varchar(10) COLLATE utf8_unicode_ci NOT NULL,
  `date` datetime NOT NULL,
  `vote` enum('+','-','0','P','X') COLLATE utf8_unicode_ci NOT NULL,
  `displayas` tinytext COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`personid`,`voteid`),
  KEY `SECONDARY` (`voteid`,`personid`),
  KEY `bydate` (`personid`,`date`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `people_committees`
--

DROP TABLE IF EXISTS `people_committees`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `people_committees` (
  `people_committee_id` int(11) NOT NULL AUTO_INCREMENT,
  `personid` int(11) NOT NULL DEFAULT '0',
  `committeeid` varchar(10) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `type` text COLLATE utf8_unicode_ci NOT NULL,
  `name` text COLLATE utf8_unicode_ci NOT NULL,
  `subname` text COLLATE utf8_unicode_ci,
  `role` text COLLATE utf8_unicode_ci,
  `housecode` text COLLATE utf8_unicode_ci NOT NULL,
  `senatecode` text COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`people_committee_id`),
  KEY `personid` (`personid`)
) ENGINE=MyISAM AUTO_INCREMENT=150841 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `committees`
--

DROP TABLE IF EXISTS `committees`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `committees` (
  `id` varchar(10) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `type` varchar(10) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `parent` varchar(10) COLLATE utf8_unicode_ci DEFAULT NULL,
  `displayname` text COLLATE utf8_unicode_ci NOT NULL,
  `thomasname` text COLLATE utf8_unicode_ci NOT NULL,
  `url` text COLLATE utf8_unicode_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `thomasname` (`thomasname`(100),`parent`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2010-01-03 17:28:17
