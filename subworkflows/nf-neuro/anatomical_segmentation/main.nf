// ** Importing modules from nf-neuro ** //
include { SEGMENTATION_FASTSEG       } from '../../../modules/nf-neuro/segmentation/fastseg/main'
include { SEGMENTATION_FREESURFERSEG } from '../../../modules/nf-neuro/segmentation/freesurferseg/main'
include { SEGMENTATION_SYNTHSEG      } from '../../../modules/nf-neuro/segmentation/synthseg/main'

params.run_synthseg = false

workflow ANATOMICAL_SEGMENTATION {

    // ** Two input channels for the segmentation processes since they are using   ** //
    // ** different image files. Supplying an empty channel for the one that isn't ** //
    // ** relevant will make the workflow run the appropriate module.              ** //
    take:
        ch_image            // channel: [ val(meta), [ image ] ]
        ch_freesurferseg    // channel: [ val(meta), [ aparc_aseg, wmparc ] ], optional
        ch_lesion           // channel: [ val(meta), [ lesion ] ], optional
        ch_fs_license       // channel: [ val[meta], [ fs_license ] ], optional

    main:

        ch_versions = channel.empty()

        if ( params.run_synthseg ) {
            // ** Freesurfer synthseg segmentation ** //
            SEGMENTATION_SYNTHSEG (
                ch_image
                    .join(ch_lesion, remainder: true)
                    .map{ it[0..1] + [it[2] ?: []] }
                    .combine(ch_fs_license)
            )
            ch_versions = ch_versions.mix(SEGMENTATION_SYNTHSEG.out.versions.first())

            // ** Setting outputs ** //
            wm_mask = SEGMENTATION_SYNTHSEG.out.wm_mask
            gm_mask = SEGMENTATION_SYNTHSEG.out.gm_mask
            csf_mask = SEGMENTATION_SYNTHSEG.out.csf_mask
            wm_map = SEGMENTATION_SYNTHSEG.out.wm_map
            gm_map = SEGMENTATION_SYNTHSEG.out.gm_map
            csf_map = SEGMENTATION_SYNTHSEG.out.csf_map
            seg = SEGMENTATION_SYNTHSEG.out.seg
            aparc_aseg = SEGMENTATION_SYNTHSEG.out.aparc_aseg
            resample = SEGMENTATION_SYNTHSEG.out.resample
            volume = SEGMENTATION_SYNTHSEG.out.volume
            qc_score = SEGMENTATION_SYNTHSEG.out.qc_score
        }

        else {
            // ** FSL fast segmentation ** //
            SEGMENTATION_FASTSEG (
                ch_image
                    .join(ch_lesion, remainder: true)
                    .map{ it[0..1] + [it[2] ?: []] }
            )
            ch_versions = ch_versions.mix(SEGMENTATION_FASTSEG.out.versions.first())

            // ** Setting outputs ** //
            wm_mask = SEGMENTATION_FASTSEG.out.wm_mask
            gm_mask = SEGMENTATION_FASTSEG.out.gm_mask
            csf_mask = SEGMENTATION_FASTSEG.out.csf_mask
            wm_map = SEGMENTATION_FASTSEG.out.wm_map
            gm_map = SEGMENTATION_FASTSEG.out.gm_map
            csf_map = SEGMENTATION_FASTSEG.out.csf_map
            seg = channel.empty()
            aparc_aseg = channel.empty()
            resample = channel.empty()
            volume = channel.empty()
            qc_score = channel.empty()


            // ** Freesurfer segmentation ** //
            SEGMENTATION_FREESURFERSEG (
                ch_freesurferseg
                    .join(ch_lesion, remainder: true)
                    .map{ it[0..2] + [it[3] ?: []] }
            )
            ch_versions = ch_versions.mix(SEGMENTATION_FREESURFERSEG.out.versions.first())

            // ** Setting outputs ** //
            wm_mask = wm_mask
                .join( SEGMENTATION_FREESURFERSEG.out.wm_mask, remainder: true )
                .map{ meta, fast, freesurfer -> [meta, freesurfer ?: fast] }
            gm_mask = gm_mask
                .join( SEGMENTATION_FREESURFERSEG.out.gm_mask, remainder: true )
                .map{ meta, fast, freesurfer -> [meta, freesurfer ?: fast] }
            csf_mask = csf_mask
                .join( SEGMENTATION_FREESURFERSEG.out.csf_mask, remainder: true )
                .map{ meta, fast, freesurfer -> [meta, freesurfer ?: fast] }
        }

    emit:
        wm_mask    = wm_mask                     // channel: [ val(meta), wm_mask ]
        gm_mask    = gm_mask                     // channel: [ val(meta), gm_mask ]
        csf_mask   = csf_mask                    // channel: [ val(meta), csf_mask ]
        wm_map     = wm_map                      // channel: [ val(meta), wm_map ]
        gm_map     = gm_map                      // channel: [ val(meta), gm_map ]
        csf_map    = csf_map                     // channel: [ val(meta), csf_map ]
        seg        = seg                         // channel: [ val(meta), seg ]
        aparc_aseg = aparc_aseg                  // channel: [ val(meta), aparc_aseg ]
        resample   = resample                    // channel: [ val(meta), resample ]
        volume     = volume                      // channel: [ val(meta), volume ]
        qc_score   = qc_score                    // channel: [ val(meta), qc_score ]

        versions  = ch_versions                  // channel: [ versions.yml ]
}
